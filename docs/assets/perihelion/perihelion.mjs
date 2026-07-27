import { march_float_round, march_float_to_string, march_int_and, march_int_div, march_int_div_euclid, march_int_mod, march_int_mod_euclid, march_int_not, march_int_or, march_int_popcount, march_int_shl, march_int_shr, march_int_xor, march_print, march_string_byte_length, march_string_concat3, march_string_join, march_string_split, march_string_to_int, march_unix_time } from "./march_runtime.mjs";

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

function Random$warmup(rng, k) {
  {
    const $t15849 = (k <= 0);
    if ($t15849 === true) {
      return rng;
    } else {
      return (() => {
        {
          const $p15851 = Random$next_raw(rng);
          {
            const r2 = $p15851._1;
            {
              const $t15850 = (k - 1);
              return Random$warmup(r2, $t15850);
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
          const $t15854 = (() => {
            {
              const $t15852 = (n - lo);
              return ($t15852 / 4294967296);
            }
          })();
          return march_int_and($t15854, 4294967295);
        }
      })();
      {
        const a = (() => {
          {
            const x$sh1_i1882 = (() => {
              {
                const $t15843_i1881 = (lo + 2654435769);
                return march_int_and($t15843_i1881, 4294967295);
              }
            })();
            {
              const x$sh2_i1885 = (() => {
                {
                  const $t15845_i1884 = (() => {
                    {
                      const $t15844_i1883 = march_int_shr(x$sh1_i1882, 16);
                      return march_int_xor(x$sh1_i1882, $t15844_i1883);
                    }
                  })();
                  {
                    const xh_i11862 = march_int_shr($t15845_i1884, 16);
                    {
                      const xl_i11863 = march_int_and($t15845_i1884, 65535);
                      {
                        const $t15834_i11868 = (() => {
                          {
                            const $t15832_i11866 = (() => {
                              {
                                const $t15831_i11865 = (() => {
                                  {
                                    const $t15830_i11864 = (xh_i11862 * 569420461);
                                    return march_int_and($t15830_i11864, 65535);
                                  }
                                })();
                                return ($t15831_i11865 * 65536);
                              }
                            })();
                            {
                              const $t15833_i11867 = (xl_i11863 * 569420461);
                              return ($t15832_i11866 + $t15833_i11867);
                            }
                          }
                        })();
                        return march_int_and($t15834_i11868, 4294967295);
                      }
                    }
                  }
                }
              })();
              {
                const x$sh3_i1888 = (() => {
                  {
                    const $t15847_i1887 = (() => {
                      {
                        const $t15846_i1886 = march_int_shr(x$sh2_i1885, 15);
                        return march_int_xor(x$sh2_i1885, $t15846_i1886);
                      }
                    })();
                    {
                      const xh_i11851 = march_int_shr($t15847_i1887, 16);
                      {
                        const xl_i11852 = march_int_and($t15847_i1887, 65535);
                        {
                          const $t15834_i11857 = (() => {
                            {
                              const $t15832_i11855 = (() => {
                                {
                                  const $t15831_i11854 = (() => {
                                    {
                                      const $t15830_i11853 = (xh_i11851 * 1935289751);
                                      return march_int_and($t15830_i11853, 65535);
                                    }
                                  })();
                                  return ($t15831_i11854 * 65536);
                                }
                              })();
                              {
                                const $t15833_i11856 = (xl_i11852 * 1935289751);
                                return ($t15832_i11855 + $t15833_i11856);
                              }
                            }
                          })();
                          return march_int_and($t15834_i11857, 4294967295);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t15848_i1889 = march_int_shr(x$sh3_i1888, 15);
                  return march_int_xor(x$sh3_i1888, $t15848_i1889);
                }
              }
            }
          }
        })();
        {
          const b = (() => {
            {
              const $t15855 = march_int_xor(hi, a);
              {
                const x$sh1_i1870 = (() => {
                  {
                    const $t15843_i1869 = ($t15855 + 2654435769);
                    return march_int_and($t15843_i1869, 4294967295);
                  }
                })();
                {
                  const x$sh2_i1873 = (() => {
                    {
                      const $t15845_i1872 = (() => {
                        {
                          const $t15844_i1871 = march_int_shr(x$sh1_i1870, 16);
                          return march_int_xor(x$sh1_i1870, $t15844_i1871);
                        }
                      })();
                      {
                        const xh_i11837 = march_int_shr($t15845_i1872, 16);
                        {
                          const xl_i11838 = march_int_and($t15845_i1872, 65535);
                          {
                            const $t15834_i11843 = (() => {
                              {
                                const $t15832_i11841 = (() => {
                                  {
                                    const $t15831_i11840 = (() => {
                                      {
                                        const $t15830_i11839 = (xh_i11837 * 569420461);
                                        return march_int_and($t15830_i11839, 65535);
                                      }
                                    })();
                                    return ($t15831_i11840 * 65536);
                                  }
                                })();
                                {
                                  const $t15833_i11842 = (xl_i11838 * 569420461);
                                  return ($t15832_i11841 + $t15833_i11842);
                                }
                              }
                            })();
                            return march_int_and($t15834_i11843, 4294967295);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const x$sh3_i1876 = (() => {
                      {
                        const $t15847_i1875 = (() => {
                          {
                            const $t15846_i1874 = march_int_shr(x$sh2_i1873, 15);
                            return march_int_xor(x$sh2_i1873, $t15846_i1874);
                          }
                        })();
                        {
                          const xh_i11826 = march_int_shr($t15847_i1875, 16);
                          {
                            const xl_i11827 = march_int_and($t15847_i1875, 65535);
                            {
                              const $t15834_i11832 = (() => {
                                {
                                  const $t15832_i11830 = (() => {
                                    {
                                      const $t15831_i11829 = (() => {
                                        {
                                          const $t15830_i11828 = (xh_i11826 * 1935289751);
                                          return march_int_and($t15830_i11828, 65535);
                                        }
                                      })();
                                      return ($t15831_i11829 * 65536);
                                    }
                                  })();
                                  {
                                    const $t15833_i11831 = (xl_i11827 * 1935289751);
                                    return ($t15832_i11830 + $t15833_i11831);
                                  }
                                }
                              })();
                              return march_int_and($t15834_i11832, 4294967295);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t15848_i1877 = march_int_shr(x$sh3_i1876, 15);
                      return march_int_xor(x$sh3_i1876, $t15848_i1877);
                    }
                  }
                }
              }
            }
          })();
          {
            const c = (() => {
              {
                const $t15856 = march_int_xor(lo, b);
                {
                  const x$sh1_i1858 = (() => {
                    {
                      const $t15843_i1857 = ($t15856 + 2654435769);
                      return march_int_and($t15843_i1857, 4294967295);
                    }
                  })();
                  {
                    const x$sh2_i1861 = (() => {
                      {
                        const $t15845_i1860 = (() => {
                          {
                            const $t15844_i1859 = march_int_shr(x$sh1_i1858, 16);
                            return march_int_xor(x$sh1_i1858, $t15844_i1859);
                          }
                        })();
                        {
                          const xh_i11812 = march_int_shr($t15845_i1860, 16);
                          {
                            const xl_i11813 = march_int_and($t15845_i1860, 65535);
                            {
                              const $t15834_i11818 = (() => {
                                {
                                  const $t15832_i11816 = (() => {
                                    {
                                      const $t15831_i11815 = (() => {
                                        {
                                          const $t15830_i11814 = (xh_i11812 * 569420461);
                                          return march_int_and($t15830_i11814, 65535);
                                        }
                                      })();
                                      return ($t15831_i11815 * 65536);
                                    }
                                  })();
                                  {
                                    const $t15833_i11817 = (xl_i11813 * 569420461);
                                    return ($t15832_i11816 + $t15833_i11817);
                                  }
                                }
                              })();
                              return march_int_and($t15834_i11818, 4294967295);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const x$sh3_i1864 = (() => {
                        {
                          const $t15847_i1863 = (() => {
                            {
                              const $t15846_i1862 = march_int_shr(x$sh2_i1861, 15);
                              return march_int_xor(x$sh2_i1861, $t15846_i1862);
                            }
                          })();
                          {
                            const xh_i11801 = march_int_shr($t15847_i1863, 16);
                            {
                              const xl_i11802 = march_int_and($t15847_i1863, 65535);
                              {
                                const $t15834_i11807 = (() => {
                                  {
                                    const $t15832_i11805 = (() => {
                                      {
                                        const $t15831_i11804 = (() => {
                                          {
                                            const $t15830_i11803 = (xh_i11801 * 1935289751);
                                            return march_int_and($t15830_i11803, 65535);
                                          }
                                        })();
                                        return ($t15831_i11804 * 65536);
                                      }
                                    })();
                                    {
                                      const $t15833_i11806 = (xl_i11802 * 1935289751);
                                      return ($t15832_i11805 + $t15833_i11806);
                                    }
                                  }
                                })();
                                return march_int_and($t15834_i11807, 4294967295);
                              }
                            }
                          }
                        }
                      })();
                      {
                        const $t15848_i1865 = march_int_shr(x$sh3_i1864, 15);
                        return march_int_xor(x$sh3_i1864, $t15848_i1865);
                      }
                    }
                  }
                }
              }
            })();
            {
              const $t15857 = ({ s0: a, s1: b, s2: c, s3: 1 });
              return Random$warmup($t15857, 12);
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
        const $t15862 = (() => {
          {
            const $t15860 = (() => {
              {
                const $t15858 = rng.s0;
                {
                  const $t15859 = rng.s1;
                  return ($t15858 + $t15859);
                }
              }
            })();
            {
              const $t15861 = rng.s3;
              return ($t15860 + $t15861);
            }
          }
        })();
        return march_int_and($t15862, 4294967295);
      }
    })();
    {
      const a = (() => {
        {
          const $t15863 = rng.s1;
          {
            const $t15865 = (() => {
              {
                const $t15864 = rng.s1;
                return march_int_shr($t15864, 9);
              }
            })();
            return march_int_xor($t15863, $t15865);
          }
        }
      })();
      {
        const b = (() => {
          {
            const $t15870 = (() => {
              {
                const $t15866 = rng.s2;
                {
                  const $t15869 = (() => {
                    {
                      const $t15868 = (() => {
                        {
                          const $t15867 = rng.s2;
                          return march_int_shl($t15867, 3);
                        }
                      })();
                      return march_int_and($t15868, 4294967295);
                    }
                  })();
                  return ($t15866 + $t15869);
                }
              }
            })();
            return march_int_and($t15870, 4294967295);
          }
        })();
        {
          const c = (() => {
            {
              const $t15873 = (() => {
                {
                  const $t15872 = (() => {
                    {
                      const $t15871 = rng.s2;
                      {
                        const keep_i1907 = (() => {
                          {
                            const $t15837_i1906 = march_int_shr(4294967295, 21);
                            return march_int_and($t15871, $t15837_i1906);
                          }
                        })();
                        {
                          const $t15838_i1908 = march_int_shl(keep_i1907, 21);
                          {
                            const $t15840_i1910 = march_int_shr($t15871, 11);
                            return march_int_or($t15838_i1908, $t15840_i1910);
                          }
                        }
                      }
                    }
                  })();
                  return ($t15872 + t);
                }
              })();
              return march_int_and($t15873, 4294967295);
            }
          })();
          {
            const $t15877 = (() => {
              {
                const $t15876 = (() => {
                  {
                    const $t15875 = (() => {
                      {
                        const $t15874 = rng.s3;
                        return ($t15874 + 1);
                      }
                    })();
                    return march_int_and($t15875, 4294967295);
                  }
                })();
                return ({ s0: a, s1: b, s2: c, s3: $t15876 });
              }
            })();
            return { _0: t, _1: $t15877 };
          }
        }
      }
    }
  }
}
const Random$next_raw$clo = { _0: ($_, rng) => Random$next_raw(rng) };

function Dom$find(id) {
  {
    const $rc_536 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_536;
  }
}
const Dom$find$clo = { _0: ($_, id) => Dom$find(id) };

function Dom$set_attr(el, name, val) {
  {
    const $rc_556 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_556;
  }
}
const Dom$set_attr$clo = { _0: ($_, el, name, val) => Dom$set_attr(el, name, val) };

function Dom$taps(el) {
  {
    const $rc_576 = dom_taps$clo._0(dom_taps$clo, el);
    return $rc_576;
  }
}
const Dom$taps$clo = { _0: ($_, el) => Dom$taps(el) };

function Dom$store_get(key) {
  {
    const $rc_577 = dom_store_get$clo._0(dom_store_get$clo, key);
    return $rc_577;
  }
}
const Dom$store_get$clo = { _0: ($_, key) => Dom$store_get(key) };

function Dom$store_set(key, val) {
  {
    const $rc_578 = dom_store_set$clo._0(dom_store_set$clo, key, val);
    return $rc_578;
  }
}
const Dom$store_set$clo = { _0: ($_, key, val) => Dom$store_set(key, val) };

function Dom$pointer_pos(el) {
  {
    const $rc_579 = dom_pointer_pos$clo._0(dom_pointer_pos$clo, el);
    return $rc_579;
  }
}
const Dom$pointer_pos$clo = { _0: ($_, el) => Dom$pointer_pos(el) };

function Dom$on_frame(cb) {
  return dom_request_animation_frame$clo._0(dom_request_animation_frame$clo, cb);
}
const Dom$on_frame$clo = { _0: ($_, cb) => Dom$on_frame(cb) };

function Canvas$get_context(node) {
  {
    const $rc_582 = canvas_get_context$clo._0(canvas_get_context$clo, node);
    return $rc_582;
  }
}
const Canvas$get_context$clo = { _0: ($_, node) => Canvas$get_context(node) };

function Canvas$save(ctx) {
  {
    const $rc_583 = canvas_save$clo._0(canvas_save$clo, ctx);
    return $rc_583;
  }
}
const Canvas$save$clo = { _0: ($_, ctx) => Canvas$save(ctx) };

function Canvas$restore(ctx) {
  {
    const $rc_584 = canvas_restore$clo._0(canvas_restore$clo, ctx);
    return $rc_584;
  }
}
const Canvas$restore$clo = { _0: ($_, ctx) => Canvas$restore(ctx) };

function Canvas$translate(ctx, x, y) {
  {
    const $rc_585 = canvas_translate$clo._0(canvas_translate$clo, ctx, x, y);
    return $rc_585;
  }
}
const Canvas$translate$clo = { _0: ($_, ctx, x, y) => Canvas$translate(ctx, x, y) };

function Canvas$rotate(ctx, angle) {
  {
    const $rc_586 = canvas_rotate$clo._0(canvas_rotate$clo, ctx, angle);
    return $rc_586;
  }
}
const Canvas$rotate$clo = { _0: ($_, ctx, angle) => Canvas$rotate(ctx, angle) };

function Canvas$set_fill_style(ctx, color) {
  {
    const $rc_588 = canvas_set_fill_style$clo._0(canvas_set_fill_style$clo, ctx, color);
    return $rc_588;
  }
}
const Canvas$set_fill_style$clo = { _0: ($_, ctx, color) => Canvas$set_fill_style(ctx, color) };

function Canvas$set_stroke_style(ctx, color) {
  {
    const $rc_589 = canvas_set_stroke_style$clo._0(canvas_set_stroke_style$clo, ctx, color);
    return $rc_589;
  }
}
const Canvas$set_stroke_style$clo = { _0: ($_, ctx, color) => Canvas$set_stroke_style(ctx, color) };

function Canvas$set_line_width(ctx, w) {
  {
    const $rc_590 = canvas_set_line_width$clo._0(canvas_set_line_width$clo, ctx, w);
    return $rc_590;
  }
}
const Canvas$set_line_width$clo = { _0: ($_, ctx, w) => Canvas$set_line_width(ctx, w) };

function Canvas$set_global_alpha(ctx, a) {
  {
    const $rc_591 = canvas_set_global_alpha$clo._0(canvas_set_global_alpha$clo, ctx, a);
    return $rc_591;
  }
}
const Canvas$set_global_alpha$clo = { _0: ($_, ctx, a) => Canvas$set_global_alpha(ctx, a) };

function Canvas$set_font(ctx, font) {
  {
    const $rc_592 = canvas_set_font$clo._0(canvas_set_font$clo, ctx, font);
    return $rc_592;
  }
}
const Canvas$set_font$clo = { _0: ($_, ctx, font) => Canvas$set_font(ctx, font) };

function Canvas$fill_rect(ctx, x, y, w, h) {
  {
    const $rc_594 = canvas_fill_rect$clo._0(canvas_fill_rect$clo, ctx, x, y, w, h);
    return $rc_594;
  }
}
const Canvas$fill_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$fill_rect(ctx, x, y, w, h) };

function Canvas$stroke_rect(ctx, x, y, w, h) {
  {
    const $rc_595 = canvas_stroke_rect$clo._0(canvas_stroke_rect$clo, ctx, x, y, w, h);
    return $rc_595;
  }
}
const Canvas$stroke_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$stroke_rect(ctx, x, y, w, h) };

function Canvas$begin_path(ctx) {
  {
    const $rc_596 = canvas_begin_path$clo._0(canvas_begin_path$clo, ctx);
    return $rc_596;
  }
}
const Canvas$begin_path$clo = { _0: ($_, ctx) => Canvas$begin_path(ctx) };

function Canvas$close_path(ctx) {
  {
    const $rc_597 = canvas_close_path$clo._0(canvas_close_path$clo, ctx);
    return $rc_597;
  }
}
const Canvas$close_path$clo = { _0: ($_, ctx) => Canvas$close_path(ctx) };

function Canvas$move_to(ctx, x, y) {
  {
    const $rc_598 = canvas_move_to$clo._0(canvas_move_to$clo, ctx, x, y);
    return $rc_598;
  }
}
const Canvas$move_to$clo = { _0: ($_, ctx, x, y) => Canvas$move_to(ctx, x, y) };

function Canvas$line_to(ctx, x, y) {
  {
    const $rc_599 = canvas_line_to$clo._0(canvas_line_to$clo, ctx, x, y);
    return $rc_599;
  }
}
const Canvas$line_to$clo = { _0: ($_, ctx, x, y) => Canvas$line_to(ctx, x, y) };

function Canvas$arc(ctx, x, y, radius, start_angle, end_angle) {
  {
    const $rc_600 = canvas_arc$clo._0(canvas_arc$clo, ctx, x, y, radius, start_angle, end_angle);
    return $rc_600;
  }
}
const Canvas$arc$clo = { _0: ($_, ctx, x, y, radius, start_angle, end_angle) => Canvas$arc(ctx, x, y, radius, start_angle, end_angle) };

function Canvas$fill(ctx) {
  {
    const $rc_603 = canvas_fill$clo._0(canvas_fill$clo, ctx);
    return $rc_603;
  }
}
const Canvas$fill$clo = { _0: ($_, ctx) => Canvas$fill(ctx) };

function Canvas$stroke(ctx) {
  {
    const $rc_604 = canvas_stroke$clo._0(canvas_stroke$clo, ctx);
    return $rc_604;
  }
}
const Canvas$stroke$clo = { _0: ($_, ctx) => Canvas$stroke(ctx) };

function Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) {
  {
    const $rc_605 = canvas_fill_noise_circle$clo._0(canvas_fill_noise_circle$clo, ctx, cx, cy, radius, alpha);
    return $rc_605;
  }
}
const Canvas$fill_noise_circle$clo = { _0: ($_, ctx, cx, cy, radius, alpha) => Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) };

function Canvas$fill_text(ctx, text, x, y) {
  {
    const $rc_606 = canvas_fill_text$clo._0(canvas_fill_text$clo, ctx, text, x, y);
    return $rc_606;
  }
}
const Canvas$fill_text$clo = { _0: ($_, ctx, text, x, y) => Canvas$fill_text(ctx, text, x, y) };

function Canvas$set_text_align(ctx, align) {
  {
    const $rc_608 = canvas_set_text_align$clo._0(canvas_set_text_align$clo, ctx, align);
    return $rc_608;
  }
}
const Canvas$set_text_align$clo = { _0: ($_, ctx, align) => Canvas$set_text_align(ctx, align) };

function Audio$resume(actx) {
  {
    const $rc_612 = audio_resume$clo._0(audio_resume$clo, actx);
    return $rc_612;
  }
}
const Audio$resume$clo = { _0: ($_, actx) => Audio$resume(actx) };

function Audio$beep(actx, freq, duration, wave) {
  {
    const $rc_613 = audio_beep$clo._0(audio_beep$clo, actx, freq, duration, wave);
    return $rc_613;
  }
}
const Audio$beep$clo = { _0: ($_, actx, freq, duration, wave) => Audio$beep(actx, freq, duration, wave) };

function Audio$sweep(actx, freq_from, freq_to, duration, wave) {
  {
    const $rc_614 = audio_sweep$clo._0(audio_sweep$clo, actx, freq_from, freq_to, duration, wave);
    return $rc_614;
  }
}
const Audio$sweep$clo = { _0: ($_, actx, freq_from, freq_to, duration, wave) => Audio$sweep(actx, freq_from, freq_to, duration, wave) };

function Audio$noise_burst(actx, duration, filter_freq) {
  {
    const $rc_615 = audio_noise_burst$clo._0(audio_noise_burst$clo, actx, duration, filter_freq);
    return $rc_615;
  }
}
const Audio$noise_burst$clo = { _0: ($_, actx, duration, filter_freq) => Audio$noise_burst(actx, duration, filter_freq) };

function Perihelion$Combat$starkiller_target_idx(game) {
  {
    const raw = (() => {
      {
        const $t27618 = (() => {
          {
            const $t27617 = game.current;
            return ($t27617 + 1);
          }
        })();
        {
          const $t27619 = game.starkiller_target_offset;
          return ($t27618 + $t27619);
        }
      }
    })();
    {
      const max_idx = (() => {
        {
          const $t27621 = (() => {
            {
              const $t27620 = game.stars;
              {
                const go_i4481 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                return go$apply$4761(go_i4481, $t27620, 0);
              }
            }
          })();
          return ($t27621 - 1);
        }
      })();
      {
        const $t27622 = (raw > max_idx);
        if ($t27622 === true) {
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
        const $t27631 = game.spawn_timer;
        return ($t27631 - dt_s);
      }
    })();
    {
      const $t27632 = (t > 0.);
      if ($t27632 === true) {
        return ({ ...game, spawn_timer: t });
      } else {
        return (() => {
          {
            const $p27658 = (() => {
              {
                const $t27633 = game.rng;
                {
                  const $p29281_i5129_i11905 = (() => {
                    {
                      const $p15886_i12597 = (() => {
                        {
                          const $p15883_i1921_i12588 = Random$next_raw($t27633);
                          {
                            const hi_i1922_i12589 = $p15883_i1921_i12588._0;
                            {
                              const rng2_i1923_i12590 = $p15883_i1921_i12588._1;
                              {
                                const $p15882_i1924_i12591 = Random$next_raw(rng2_i1923_i12590);
                                {
                                  const lo_i1925_i12592 = $p15882_i1924_i12591._0;
                                  {
                                    const rng3_i1926_i12593 = $p15882_i1924_i12591._1;
                                    {
                                      const $t15881_i1930_i12596 = (() => {
                                        {
                                          const $t15880_i1929_i12595 = (() => {
                                            {
                                              const $t15878_i1927_i12594 = march_int_and(hi_i1922_i12589, 1048575);
                                              return ($t15878_i1927_i12594 * 4294967296);
                                            }
                                          })();
                                          return ($t15880_i1929_i12595 + lo_i1925_i12592);
                                        }
                                      })();
                                      return { _0: $t15881_i1930_i12596, _1: rng3_i1926_i12593 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i12598 = $p15886_i12597._0;
                        {
                          const rng2_i12599 = $p15886_i12597._1;
                          {
                            const $t15885_i12601 = (() => {
                              {
                                const $t15884_i12600 = bits_i12598;
                                return ($t15884_i12600 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15885_i12601, _1: rng2_i12599 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i5130_i11906 = $p29281_i5129_i11905._0;
                    {
                      const rng2_i5131_i11907 = $p29281_i5129_i11905._1;
                      {
                        const out_i5132_i11908 = { _0: rng2_i5131_i11907, _1: t_i5130_i11906 };
                        return out_i5132_i11908;
                      }
                    }
                  }
                }
              }
            })();
            {
              const r1 = $p27658._0;
              {
                const side_f = $p27658._1;
                {
                  const $p27657 = (() => {
                    {
                      const $p29281_i5129_i11900 = (() => {
                        {
                          const $p15886_i12582 = (() => {
                            {
                              const $p15883_i1921_i12573 = Random$next_raw(r1);
                              {
                                const hi_i1922_i12574 = $p15883_i1921_i12573._0;
                                {
                                  const rng2_i1923_i12575 = $p15883_i1921_i12573._1;
                                  {
                                    const $p15882_i1924_i12576 = Random$next_raw(rng2_i1923_i12575);
                                    {
                                      const lo_i1925_i12577 = $p15882_i1924_i12576._0;
                                      {
                                        const rng3_i1926_i12578 = $p15882_i1924_i12576._1;
                                        {
                                          const $t15881_i1930_i12581 = (() => {
                                            {
                                              const $t15880_i1929_i12580 = (() => {
                                                {
                                                  const $t15878_i1927_i12579 = march_int_and(hi_i1922_i12574, 1048575);
                                                  return ($t15878_i1927_i12579 * 4294967296);
                                                }
                                              })();
                                              return ($t15880_i1929_i12580 + lo_i1925_i12577);
                                            }
                                          })();
                                          return { _0: $t15881_i1930_i12581, _1: rng3_i1926_i12578 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const bits_i12583 = $p15886_i12582._0;
                            {
                              const rng2_i12584 = $p15886_i12582._1;
                              {
                                const $t15885_i12586 = (() => {
                                  {
                                    const $t15884_i12585 = bits_i12583;
                                    return ($t15884_i12585 / 4.50359962737e+15);
                                  }
                                })();
                                return { _0: $t15885_i12586, _1: rng2_i12584 };
                              }
                            }
                          }
                        }
                      })();
                      {
                        const t_i5130_i11901 = $p29281_i5129_i11900._0;
                        {
                          const rng2_i5131_i11902 = $p29281_i5129_i11900._1;
                          {
                            const out_i5132_i11903 = { _0: rng2_i5131_i11902, _1: t_i5130_i11901 };
                            return out_i5132_i11903;
                          }
                        }
                      }
                    }
                  })();
                  {
                    const r2 = $p27657._0;
                    {
                      const y_f = $p27657._1;
                      {
                        const $p27656 = (() => {
                          {
                            const $p29281_i5129_i11895 = (() => {
                              {
                                const $p15886_i12567 = (() => {
                                  {
                                    const $p15883_i1921_i12558 = Random$next_raw(r2);
                                    {
                                      const hi_i1922_i12559 = $p15883_i1921_i12558._0;
                                      {
                                        const rng2_i1923_i12560 = $p15883_i1921_i12558._1;
                                        {
                                          const $p15882_i1924_i12561 = Random$next_raw(rng2_i1923_i12560);
                                          {
                                            const lo_i1925_i12562 = $p15882_i1924_i12561._0;
                                            {
                                              const rng3_i1926_i12563 = $p15882_i1924_i12561._1;
                                              {
                                                const $t15881_i1930_i12566 = (() => {
                                                  {
                                                    const $t15880_i1929_i12565 = (() => {
                                                      {
                                                        const $t15878_i1927_i12564 = march_int_and(hi_i1922_i12559, 1048575);
                                                        return ($t15878_i1927_i12564 * 4294967296);
                                                      }
                                                    })();
                                                    return ($t15880_i1929_i12565 + lo_i1925_i12562);
                                                  }
                                                })();
                                                return { _0: $t15881_i1930_i12566, _1: rng3_i1926_i12563 };
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const bits_i12568 = $p15886_i12567._0;
                                  {
                                    const rng2_i12569 = $p15886_i12567._1;
                                    {
                                      const $t15885_i12571 = (() => {
                                        {
                                          const $t15884_i12570 = bits_i12568;
                                          return ($t15884_i12570 / 4.50359962737e+15);
                                        }
                                      })();
                                      return { _0: $t15885_i12571, _1: rng2_i12569 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const t_i5130_i11896 = $p29281_i5129_i11895._0;
                              {
                                const rng2_i5131_i11897 = $p29281_i5129_i11895._1;
                                {
                                  const out_i5132_i11898 = { _0: rng2_i5131_i11897, _1: t_i5130_i11896 };
                                  return out_i5132_i11898;
                                }
                              }
                            }
                          }
                        })();
                        {
                          const r3 = $p27656._0;
                          {
                            const ang_f = $p27656._1;
                            {
                              const $p27655 = (() => {
                                {
                                  const $p29281_i5129_i11890 = (() => {
                                    {
                                      const $p15886_i12552 = (() => {
                                        {
                                          const $p15883_i1921_i12543 = Random$next_raw(r3);
                                          {
                                            const hi_i1922_i12544 = $p15883_i1921_i12543._0;
                                            {
                                              const rng2_i1923_i12545 = $p15883_i1921_i12543._1;
                                              {
                                                const $p15882_i1924_i12546 = Random$next_raw(rng2_i1923_i12545);
                                                {
                                                  const lo_i1925_i12547 = $p15882_i1924_i12546._0;
                                                  {
                                                    const rng3_i1926_i12548 = $p15882_i1924_i12546._1;
                                                    {
                                                      const $t15881_i1930_i12551 = (() => {
                                                        {
                                                          const $t15880_i1929_i12550 = (() => {
                                                            {
                                                              const $t15878_i1927_i12549 = march_int_and(hi_i1922_i12544, 1048575);
                                                              return ($t15878_i1927_i12549 * 4294967296);
                                                            }
                                                          })();
                                                          return ($t15880_i1929_i12550 + lo_i1925_i12547);
                                                        }
                                                      })();
                                                      return { _0: $t15881_i1930_i12551, _1: rng3_i1926_i12548 };
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const bits_i12553 = $p15886_i12552._0;
                                        {
                                          const rng2_i12554 = $p15886_i12552._1;
                                          {
                                            const $t15885_i12556 = (() => {
                                              {
                                                const $t15884_i12555 = bits_i12553;
                                                return ($t15884_i12555 / 4.50359962737e+15);
                                              }
                                            })();
                                            return { _0: $t15885_i12556, _1: rng2_i12554 };
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const t_i5130_i11891 = $p29281_i5129_i11890._0;
                                    {
                                      const rng2_i5131_i11892 = $p29281_i5129_i11890._1;
                                      {
                                        const out_i5132_i11893 = { _0: rng2_i5131_i11892, _1: t_i5130_i11891 };
                                        return out_i5132_i11893;
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const r4 = $p27655._0;
                                {
                                  const next_f = $p27655._1;
                                  {
                                    const $p27654 = (() => {
                                      {
                                        const $p29281_i5129_i11885 = (() => {
                                          {
                                            const $p15886_i12537 = (() => {
                                              {
                                                const $p15883_i1921_i12528 = Random$next_raw(r4);
                                                {
                                                  const hi_i1922_i12529 = $p15883_i1921_i12528._0;
                                                  {
                                                    const rng2_i1923_i12530 = $p15883_i1921_i12528._1;
                                                    {
                                                      const $p15882_i1924_i12531 = Random$next_raw(rng2_i1923_i12530);
                                                      {
                                                        const lo_i1925_i12532 = $p15882_i1924_i12531._0;
                                                        {
                                                          const rng3_i1926_i12533 = $p15882_i1924_i12531._1;
                                                          {
                                                            const $t15881_i1930_i12536 = (() => {
                                                              {
                                                                const $t15880_i1929_i12535 = (() => {
                                                                  {
                                                                    const $t15878_i1927_i12534 = march_int_and(hi_i1922_i12529, 1048575);
                                                                    return ($t15878_i1927_i12534 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15880_i1929_i12535 + lo_i1925_i12532);
                                                              }
                                                            })();
                                                            return { _0: $t15881_i1930_i12536, _1: rng3_i1926_i12533 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i12538 = $p15886_i12537._0;
                                              {
                                                const rng2_i12539 = $p15886_i12537._1;
                                                {
                                                  const $t15885_i12541 = (() => {
                                                    {
                                                      const $t15884_i12540 = bits_i12538;
                                                      return ($t15884_i12540 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15885_i12541, _1: rng2_i12539 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i5130_i11886 = $p29281_i5129_i11885._0;
                                          {
                                            const rng2_i5131_i11887 = $p29281_i5129_i11885._1;
                                            {
                                              const out_i5132_i11888 = { _0: rng2_i5131_i11887, _1: t_i5130_i11886 };
                                              return out_i5132_i11888;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const r5 = $p27654._0;
                                      {
                                        const shape_f = $p27654._1;
                                        {
                                          const from_left = (side_f < 0.5);
                                          {
                                            let x;
                                            if (from_left === true) {
                                              x = (0. - 20.);
                                            } else {
                                              x = (() => {
                                                {
                                                  const $t27634 = game.view_w;
                                                  return ($t27634 + 20.);
                                                }
                                              })();
                                            }
                                            {
                                              const y = (() => {
                                                {
                                                  const $t27635 = game.camera_y;
                                                  {
                                                    const $t27637 = (() => {
                                                      {
                                                        const $t27636 = game.view_h;
                                                        return (y_f * $t27636);
                                                      }
                                                    })();
                                                    return ($t27635 + $t27637);
                                                  }
                                                }
                                              })();
                                              {
                                                const jitter = (() => {
                                                  {
                                                    const $t27638 = (ang_f - 0.5);
                                                    return ($t27638 * 1.0472);
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
                                                        const $t27640 = (dir_x * 90.);
                                                        {
                                                          const $t27641 = Math.cos(jitter);
                                                          return ($t27640 * $t27641);
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const vy = (() => {
                                                        {
                                                          const $t27643 = Math.sin(jitter);
                                                          return (90. * $t27643);
                                                        }
                                                      })();
                                                      {
                                                        const a = (() => {
                                                          {
                                                            const $t27645 = { $: "AsteroidDrifting" };
                                                            return ({ x: x, y: y, vx: vx, vy: vy, radius: 10., shape_seed: shape_f, mode: $t27645 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27646 = game.asteroids;
                                                          {
                                                            const $t27647 = (() => {
                                                              return { $: "Cons", _0: a, _1: $t27646 };
                                                            })();
                                                            {
                                                              const $t27653 = (() => {
                                                                {
                                                                  const $t27652 = (() => {
                                                                    {
                                                                      const $t27650 = (() => {
                                                                        {
                                                                          const $t27649 = (next_f - 0.5);
                                                                          return ($t27649 * 2.);
                                                                        }
                                                                      })();
                                                                      return ($t27650 * 1.);
                                                                    }
                                                                  })();
                                                                  return (4. + $t27652);
                                                                }
                                                              })();
                                                              return ({ ...game, asteroids: $t27647, rng: r5, spawn_timer: $t27653 });
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
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
    const $t27670 = (() => {
      {
        const $t27667 = (() => {
          {
            const $t27661 = (() => {
              {
                const $t27660 = (() => {
                  {
                    const $t27659 = game.camera_y;
                    return ($t27659 - 100.);
                  }
                })();
                return (y > $t27660);
              }
            })();
            {
              const $t27666 = (() => {
                {
                  const $t27665 = (() => {
                    {
                      const $t27664 = (() => {
                        {
                          const $t27662 = game.camera_y;
                          {
                            const $t27663 = game.view_h;
                            return ($t27662 + $t27663);
                          }
                        }
                      })();
                      return ($t27664 + 100.);
                    }
                  })();
                  return (y < $t27665);
                }
              })();
              return ($t27661 && $t27666);
            }
          }
        })();
        {
          const $t27669 = (() => {
            {
              const $t27668 = (0. - 100.);
              return (x > $t27668);
            }
          })();
          return ($t27667 && $t27669);
        }
      }
    })();
    {
      const $t27673 = (() => {
        {
          const $t27672 = (() => {
            {
              const $t27671 = game.view_w;
              return ($t27671 + 100.);
            }
          })();
          return (x < $t27672);
        }
      })();
      return ($t27670 && $t27673);
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
      const $f27683 = asteroids._0;
      const $f27684 = asteroids._1;
      {
        const rest = (() => {
          return $f27684;
        })();
        {
          const a = (() => {
            return $f27683;
          })();
          {
            const dx = (() => {
              {
                const $t27674 = a.x;
                return ($t27674 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27675 = a.y;
                  return ($t27675 - y);
                }
              })();
              {
                const d2 = (() => {
                  {
                    const $t27676 = (dx * dx);
                    {
                      const $t27677 = (dy * dy);
                      return ($t27676 + $t27677);
                    }
                  }
                })();
                {
                  const $t27678 = (d2 < best_d2);
                  if ($t27678 === true) {
                    return (() => {
                      {
                        const $t27682 = (() => {
                          {
                            const $t27679 = a.x;
                            {
                              const $t27680 = a.y;
                              {
                                const $t27681 = { _0: $t27679, _1: $t27680 };
                                return { $: "Some", _0: $t27681 };
                              }
                            }
                          }
                        })();
                        return Perihelion$Combat$nearest_in_list_ast(x, y, rest, d2, $t27682);
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
      const $f27695 = ships._0;
      const $f27696 = ships._1;
      {
        const rest = (() => {
          return $f27696;
        })();
        {
          const sh = (() => {
            return $f27695;
          })();
          {
            const pos = (() => {
              {
                const pos_i4503 = (() => {
                  {
                    const $t27623_i4501 = sh.x;
                    {
                      const $t27624_i4502 = sh.y;
                      return { _0: $t27623_i4501, _1: $t27624_i4502 };
                    }
                  }
                })();
                return pos_i4503;
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
                          const $t27689 = (dx * dx);
                          {
                            const $t27690 = (dy * dy);
                            return ($t27689 + $t27690);
                          }
                        }
                      })();
                      {
                        const $t27691 = (d2 < best_d2);
                        if ($t27691 === true) {
                          return (() => {
                            {
                              const $t27693 = (() => {
                                {
                                  const $t27692 = { _0: sx, _1: sy };
                                  return { $: "Some", _0: $t27692 };
                                }
                              })();
                              return Perihelion$Combat$nearest_in_list_ship(x, y, rest, d2, $t27693);
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
    const $p27715 = (() => {
      {
        const $t27703 = (220. * 220.);
        {
          const $t27704 = { $: "None" };
          return Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, $t27703, $t27704);
        }
      }
    })();
    {
      const d2a = $p27715._0;
      {
        const besta = $p27715._1;
        {
          const $p27714 = (() => {
            return Perihelion$Combat$nearest_in_list_ship(x, y, ships, d2a, besta);
          })();
          {
            const bests = $p27714._1;
            switch (bests.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27713 = bests._0;
                {
                  const pair = (() => {
                    return $f27713;
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
                                const $t27707 = (() => {
                                  {
                                    const $t27705 = (dx * dx);
                                    {
                                      const $t27706 = (dy * dy);
                                      return ($t27705 + $t27706);
                                    }
                                  }
                                })();
                                return Math.sqrt($t27707);
                              }
                            })();
                            {
                              const $t27708 = (d > 0.);
                              if ($t27708 === true) {
                                return (() => {
                                  {
                                    const $t27709 = (dx / d);
                                    {
                                      const $t27710 = (dy / d);
                                      {
                                        const $t27711 = { _0: $t27709, _1: $t27710 };
                                        return { $: "Some", _0: $t27711 };
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
        const $t27719 = (() => {
          {
            const $t27716 = s.x;
            {
              const $t27718 = (() => {
                {
                  const $t27717 = s.vx;
                  return ($t27717 * dt_s);
                }
              })();
              return ($t27716 + $t27718);
            }
          }
        })();
        {
          const $t27723 = (() => {
            {
              const $t27720 = s.y;
              {
                const $t27722 = (() => {
                  {
                    const $t27721 = s.vy;
                    return ($t27721 * dt_s);
                  }
                })();
                return ($t27720 + $t27722);
              }
            }
          })();
          {
            const $t27725 = (() => {
              {
                const $t27724 = s.ttl;
                return ($t27724 - dt_s);
              }
            })();
            return ({ ...s, x: $t27719, y: $t27723, ttl: $t27725 });
          }
        }
      }
    })();
    {
      const $t27727 = (() => {
        {
          const $t27726 = s.homing;
          return (!$t27726);
        }
      })();
      if ($t27727 === true) {
        return moved;
      } else {
        return (() => {
          {
            const $t27730 = (() => {
              {
                const $t27728 = s.x;
                {
                  const $t27729 = s.y;
                  return Perihelion$Combat$nearest_hazard_dir($t27728, $t27729, asteroids, ships);
                }
              }
            })();
            switch ($t27730.$) {
              case "None": {
                return moved;
                break;
              }
              case "Some": {
                const $f27756 = $t27730._0;
                {
                  const pair = $f27756;
                  {
                    const tx = pair._0;
                    {
                      const ty = pair._1;
                      {
                        const speed = (() => {
                          {
                            const $t27737 = (() => {
                              {
                                const $t27733 = (() => {
                                  {
                                    const $t27731 = s.vx;
                                    {
                                      const $t27732 = s.vx;
                                      return ($t27731 * $t27732);
                                    }
                                  }
                                })();
                                {
                                  const $t27736 = (() => {
                                    {
                                      const $t27734 = s.vy;
                                      {
                                        const $t27735 = s.vy;
                                        return ($t27734 * $t27735);
                                      }
                                    }
                                  })();
                                  return ($t27733 + $t27736);
                                }
                              }
                            })();
                            return Math.sqrt($t27737);
                          }
                        })();
                        {
                          const cur_ax = (() => {
                            {
                              const $t27738 = s.vx;
                              return ($t27738 / speed);
                            }
                          })();
                          {
                            const cur_ay = (() => {
                              {
                                const $t27739 = s.vy;
                                return ($t27739 / speed);
                              }
                            })();
                            {
                              const turned_ax = (() => {
                                {
                                  const $t27743 = (() => {
                                    {
                                      const $t27742 = (() => {
                                        {
                                          const $t27740 = (tx - cur_ax);
                                          return ($t27740 * 3.);
                                        }
                                      })();
                                      return ($t27742 * dt_s);
                                    }
                                  })();
                                  return (cur_ax + $t27743);
                                }
                              })();
                              {
                                const turned_ay = (() => {
                                  {
                                    const $t27747 = (() => {
                                      {
                                        const $t27746 = (() => {
                                          {
                                            const $t27744 = (ty - cur_ay);
                                            return ($t27744 * 3.);
                                          }
                                        })();
                                        return ($t27746 * dt_s);
                                      }
                                    })();
                                    return (cur_ay + $t27747);
                                  }
                                })();
                                {
                                  const norm = (() => {
                                    {
                                      const $t27750 = (() => {
                                        {
                                          const $t27748 = (turned_ax * turned_ax);
                                          {
                                            const $t27749 = (turned_ay * turned_ay);
                                            return ($t27748 + $t27749);
                                          }
                                        }
                                      })();
                                      return Math.sqrt($t27750);
                                    }
                                  })();
                                  {
                                    const $t27752 = (() => {
                                      {
                                        const $t27751 = (turned_ax / norm);
                                        return ($t27751 * speed);
                                      }
                                    })();
                                    {
                                      const $t27754 = (() => {
                                        {
                                          const $t27753 = (turned_ay / norm);
                                          return ($t27753 * speed);
                                        }
                                      })();
                                      return ({ ...moved, vx: $t27752, vy: $t27754 });
                                    }
                                  }
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
      const $t27757 = g1.player_shots;
      {
        const $t27761 = { $: "$Clo_$lam27758$3709", _0: $lam27758$apply$3709, _1: dt_s, _2: g1 };
        {
          const $t27762 = (() => {
            {
              const f_i4530 = $t27761;
              {
                const go_i4531 = { $: "$Clo_go$4769", _0: go$apply$4769, _1: f_i4530 };
                {
                  const $t291_i4532 = { $: "Nil" };
                  return go$apply$4769(go_i4531, $t27757, $t291_i4532);
                }
              }
            }
          })();
          {
            const $t27769 = { $: "$Clo_$lam27763$3710", _0: $lam27763$apply$3710, _1: g1 };
            {
              const p_shots = (() => {
                {
                  const pred_i4526 = $t27769;
                  {
                    const go_i4527 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4526 };
                    {
                      const $t323_i4528 = { $: "Nil" };
                      return go$apply$4767(go_i4527, $t27762, $t323_i4528);
                    }
                  }
                }
              })();
              {
                const $t27770 = g1.enemy_shots;
                {
                  const $t27774 = { $: "$Clo_$lam27771$3711", _0: $lam27771$apply$3711, _1: dt_s, _2: g1 };
                  {
                    const $t27775 = (() => {
                      {
                        const f_i4522 = $t27774;
                        {
                          const go_i4523 = { $: "$Clo_go$4769", _0: go$apply$4769, _1: f_i4522 };
                          {
                            const $t291_i4524 = { $: "Nil" };
                            return go$apply$4769(go_i4523, $t27770, $t291_i4524);
                          }
                        }
                      }
                    })();
                    {
                      const $t27782 = { $: "$Clo_$lam27776$3712", _0: $lam27776$apply$3712, _1: g1 };
                      {
                        const e_shots = (() => {
                          {
                            const pred_i4518 = $t27782;
                            {
                              const go_i4519 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4518 };
                              {
                                const $t323_i4520 = { $: "Nil" };
                                return go$apply$4767(go_i4519, $t27775, $t323_i4520);
                              }
                            }
                          }
                        })();
                        {
                          const $t27783 = g1.pickups;
                          {
                            const $t27787 = { $: "$Clo_$lam27784$3713", _0: $lam27784$apply$3713, _1: dt_s };
                            {
                              const $t27788 = (() => {
                                {
                                  const f_i4514 = $t27787;
                                  {
                                    const go_i4515 = { $: "$Clo_go$4765", _0: go$apply$4765, _1: f_i4514 };
                                    {
                                      const $t291_i4516 = { $: "Nil" };
                                      return go$apply$4765(go_i4515, $t27783, $t291_i4516);
                                    }
                                  }
                                }
                              })();
                              {
                                const $t27791 = { $: "$Clo_$lam27789$3714", _0: $lam27789$apply$3714 };
                                {
                                  const pickups = (() => {
                                    {
                                      const pred_i4510 = $t27791;
                                      {
                                        const go_i4511 = { $: "$Clo_go$4763", _0: go$apply$4763, _1: pred_i4510 };
                                        {
                                          const $t323_i4512 = { $: "Nil" };
                                          return go$apply$4763(go_i4511, $t27788, $t323_i4512);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27795 = (() => {
                                      {
                                        const $t27793 = (() => {
                                          {
                                            const $t27792 = g1.fire_cooldown;
                                            return ($t27792 > 0.);
                                          }
                                        })();
                                        if ($t27793 === true) {
                                          return (() => {
                                            {
                                              const $t27794 = g1.fire_cooldown;
                                              return ($t27794 - dt_s);
                                            }
                                          })();
                                        } else {
                                          return 0.;
                                        }
                                      }
                                    })();
                                    {
                                      const $t27799 = (() => {
                                        {
                                          const $t27797 = (() => {
                                            {
                                              const $t27796 = g1.starkiller_cooldown;
                                              return ($t27796 > 0.);
                                            }
                                          })();
                                          if ($t27797 === true) {
                                            return (() => {
                                              {
                                                const $t27798 = g1.starkiller_cooldown;
                                                return ($t27798 - dt_s);
                                              }
                                            })();
                                          } else {
                                            return 0.;
                                          }
                                        }
                                      })();
                                      return ({ ...g1, player_shots: p_shots, enemy_shots: e_shots, pickups: pickups, fire_cooldown: $t27795, starkiller_cooldown: $t27799 });
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
      const $f27806 = stars._0;
      const $f27807 = stars._1;
      {
        const rest = $f27807;
        {
          const s = $f27806;
          {
            const dx = (() => {
              {
                const $t27800 = s.x;
                return ($t27800 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27801 = s.y;
                  return ($t27801 - y);
                }
              })();
              {
                const d = (() => {
                  {
                    const $t27802 = (dx * dx);
                    {
                      const $t27803 = (dy * dy);
                      return ($t27802 + $t27803);
                    }
                  }
                })();
                {
                  const $t27804 = (d < best_d);
                  if ($t27804 === true) {
                    return (() => {
                      {
                        const $t27805 = { $: "Some", _0: s };
                        return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, $t27805, d);
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
    const $t27814 = (() => {
      {
        const $t27812 = { $: "None" };
        {
          const $t27813 = (240. * 240.);
          return Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, $t27812, $t27813);
        }
      }
    })();
    switch ($t27814.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f27840 = $t27814._0;
        {
          const s = $f27840;
          {
            const dx = (() => {
              {
                const $t27815 = s.x;
                return ($t27815 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27816 = s.y;
                  return ($t27816 - y);
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t27819 = (() => {
                      {
                        const $t27817 = (dx * dx);
                        {
                          const $t27818 = (dy * dy);
                          return ($t27817 + $t27818);
                        }
                      }
                    })();
                    return Math.sqrt($t27819);
                  }
                })();
                {
                  const $t27820 = (dist > 0.);
                  if ($t27820 === true) {
                    return (() => {
                      {
                        const speed = (() => {
                          {
                            const $t27823 = (() => {
                              {
                                const $t27821 = (vx * vx);
                                {
                                  const $t27822 = (vy * vy);
                                  return ($t27821 + $t27822);
                                }
                              }
                            })();
                            return Math.sqrt($t27823);
                          }
                        })();
                        {
                          const nvx = (() => {
                            {
                              const $t27827 = (() => {
                                {
                                  const $t27826 = (() => {
                                    {
                                      const $t27824 = (dx / dist);
                                      return ($t27824 * 500.);
                                    }
                                  })();
                                  return ($t27826 * dt_s);
                                }
                              })();
                              return (vx + $t27827);
                            }
                          })();
                          {
                            const nvy = (() => {
                              {
                                const $t27831 = (() => {
                                  {
                                    const $t27830 = (() => {
                                      {
                                        const $t27828 = (dy / dist);
                                        return ($t27828 * 500.);
                                      }
                                    })();
                                    return ($t27830 * dt_s);
                                  }
                                })();
                                return (vy + $t27831);
                              }
                            })();
                            {
                              const nspeed = (() => {
                                {
                                  const $t27834 = (() => {
                                    {
                                      const $t27832 = (nvx * nvx);
                                      {
                                        const $t27833 = (nvy * nvy);
                                        return ($t27832 + $t27833);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t27834);
                                }
                              })();
                              {
                                const $t27835 = (nspeed > 0.);
                                if ($t27835 === true) {
                                  return (() => {
                                    {
                                      const $t27837 = (() => {
                                        {
                                          const $t27836 = (nvx / nspeed);
                                          return ($t27836 * speed);
                                        }
                                      })();
                                      {
                                        const $t27839 = (() => {
                                          {
                                            const $t27838 = (nvy / nspeed);
                                            return ($t27838 * speed);
                                          }
                                        })();
                                        return { _0: $t27837, _1: $t27839 };
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
        const $t27841 = (() => {
          {
            const go_i4540 = { $: "$Clo_go$4771", _0: go$apply$4771 };
            {
              const $t274_i4541 = { $: "Nil" };
              return go$apply$4771(go_i4540, acc, $t274_i4541);
            }
          }
        })();
        return ({ ...game, asteroids: $t27841 });
      }
      break;
    }
    case "Cons": {
      const $f27905 = asteroids._0;
      const $f27906 = asteroids._1;
      {
        const rest = $f27906;
        {
          const a = $f27905;
          {
            const $t27842 = a.mode;
            switch ($t27842.$) {
              case "AsteroidOrbiting": {
                const $f27899 = $t27842._0;
                const $f27900 = $t27842._1;
                {
                  const angle = (() => {
                    return $f27900;
                  })();
                  {
                    const idx = (() => {
                      return $f27899;
                    })();
                    {
                      const $t27843 = Perihelion$Core$star_at(game, idx);
                      switch ($t27843.$) {
                        case "None": {
                          return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                          break;
                        }
                        case "Some": {
                          const $f27858 = $t27843._0;
                          {
                            const s = $f27858;
                            {
                              const angle2 = (() => {
                                {
                                  const $t27845 = (1. * dt_s);
                                  return (angle + $t27845);
                                }
                              })();
                              {
                                const r = (() => {
                                  {
                                    const $t27846 = s.capture_radius;
                                    return ($t27846 * 0.8);
                                  }
                                })();
                                {
                                  const a2 = (() => {
                                    {
                                      const $t27851 = (() => {
                                        {
                                          const $t27848 = s.x;
                                          {
                                            const $t27850 = (() => {
                                              {
                                                const $t27849 = Math.cos(angle2);
                                                return ($t27849 * r);
                                              }
                                            })();
                                            return ($t27848 + $t27850);
                                          }
                                        }
                                      })();
                                      {
                                        const $t27855 = (() => {
                                          {
                                            const $t27852 = s.y;
                                            {
                                              const $t27854 = (() => {
                                                {
                                                  const $t27853 = Math.sin(angle2);
                                                  return ($t27853 * r);
                                                }
                                              })();
                                              return ($t27852 + $t27854);
                                            }
                                          }
                                        })();
                                        {
                                          const $t27856 = { $: "AsteroidOrbiting", _0: idx, _1: angle2 };
                                          return ({ ...a, x: $t27851, y: $t27855, mode: $t27856 });
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27857 = { $: "Cons", _0: a2, _1: acc };
                                    return Perihelion$Combat$step_asteroids_go(game, rest, $t27857, dt_s);
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
                      const $t27859 = a.x;
                      {
                        const $t27860 = a.y;
                        {
                          const $t27861 = a.vx;
                          {
                            const $t27862 = a.vy;
                            {
                              const $t27863 = game.stars;
                              return Perihelion$Combat$arc_velocity($t27859, $t27860, $t27861, $t27862, $t27863, dt_s);
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
                            const $t27864 = a.x;
                            {
                              const $t27865 = (vx2 * dt_s);
                              return ($t27864 + $t27865);
                            }
                          }
                        })();
                        {
                          const y2 = (() => {
                            {
                              const $t27866 = a.y;
                              {
                                const $t27867 = (vy2 * dt_s);
                                return ($t27866 + $t27867);
                              }
                            }
                          })();
                          {
                            const $t27869 = (() => {
                              {
                                const $t27868 = Perihelion$Combat$in_band(game, x2, y2);
                                return (!$t27868);
                              }
                            })();
                            if ($t27869 === true) {
                              return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                            } else {
                              return (() => {
                                {
                                  const $t27871 = (() => {
                                    {
                                      const $t27870 = game.stars;
                                      return Perihelion$Combat$arrived_star($t27870, x2, y2, 0);
                                    }
                                  })();
                                  switch ($t27871.$) {
                                    case "None": {
                                      {
                                        const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                        {
                                          const $t27872 = { $: "Cons", _0: a2, _1: acc };
                                          return Perihelion$Combat$step_asteroids_go(game, rest, $t27872, dt_s);
                                        }
                                      }
                                      break;
                                    }
                                    case "Some": {
                                      const $f27897 = $t27871._0;
                                      {
                                        const pair = $f27897;
                                        {
                                          const idx = pair._0;
                                          {
                                            const s = pair._1;
                                            {
                                              const $p27895 = (() => {
                                                {
                                                  const $t27873 = game.rng;
                                                  {
                                                    const $p29281_i5129_i11910 = (() => {
                                                      {
                                                        const $p15886_i12612 = (() => {
                                                          {
                                                            const $p15883_i1921_i12603 = Random$next_raw($t27873);
                                                            {
                                                              const hi_i1922_i12604 = $p15883_i1921_i12603._0;
                                                              {
                                                                const rng2_i1923_i12605 = $p15883_i1921_i12603._1;
                                                                {
                                                                  const $p15882_i1924_i12606 = Random$next_raw(rng2_i1923_i12605);
                                                                  {
                                                                    const lo_i1925_i12607 = $p15882_i1924_i12606._0;
                                                                    {
                                                                      const rng3_i1926_i12608 = $p15882_i1924_i12606._1;
                                                                      {
                                                                        const $t15881_i1930_i12611 = (() => {
                                                                          {
                                                                            const $t15880_i1929_i12610 = (() => {
                                                                              {
                                                                                const $t15878_i1927_i12609 = march_int_and(hi_i1922_i12604, 1048575);
                                                                                return ($t15878_i1927_i12609 * 4294967296);
                                                                              }
                                                                            })();
                                                                            return ($t15880_i1929_i12610 + lo_i1925_i12607);
                                                                          }
                                                                        })();
                                                                        return { _0: $t15881_i1930_i12611, _1: rng3_i1926_i12608 };
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const bits_i12613 = $p15886_i12612._0;
                                                          {
                                                            const rng2_i12614 = $p15886_i12612._1;
                                                            {
                                                              const $t15885_i12616 = (() => {
                                                                {
                                                                  const $t15884_i12615 = bits_i12613;
                                                                  return ($t15884_i12615 / 4.50359962737e+15);
                                                                }
                                                              })();
                                                              return { _0: $t15885_i12616, _1: rng2_i12614 };
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const t_i5130_i11911 = $p29281_i5129_i11910._0;
                                                      {
                                                        const rng2_i5131_i11912 = $p29281_i5129_i11910._1;
                                                        {
                                                          const out_i5132_i11913 = { _0: rng2_i5131_i11912, _1: t_i5130_i11911 };
                                                          return out_i5132_i11913;
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const rng2 = $p27895._0;
                                                {
                                                  const roll = $p27895._1;
                                                  {
                                                    const $t27875 = (roll < 0.35);
                                                    if ($t27875 === true) {
                                                      return (() => {
                                                        {
                                                          const angle = (() => {
                                                            {
                                                              const $t27877 = (() => {
                                                                {
                                                                  const $t27876 = s.y;
                                                                  return (y2 - $t27876);
                                                                }
                                                              })();
                                                              {
                                                                const $t27879 = (() => {
                                                                  {
                                                                    const $t27878 = s.x;
                                                                    return (x2 - $t27878);
                                                                  }
                                                                })();
                                                                return Math.atan2($t27877, $t27879);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const r = (() => {
                                                              {
                                                                const $t27880 = s.capture_radius;
                                                                return ($t27880 * 0.8);
                                                              }
                                                            })();
                                                            {
                                                              const a2 = (() => {
                                                                {
                                                                  const $t27885 = (() => {
                                                                    {
                                                                      const $t27882 = s.x;
                                                                      {
                                                                        const $t27884 = (() => {
                                                                          {
                                                                            const $t27883 = Math.cos(angle);
                                                                            return ($t27883 * r);
                                                                          }
                                                                        })();
                                                                        return ($t27882 + $t27884);
                                                                      }
                                                                    }
                                                                  })();
                                                                  {
                                                                    const $t27889 = (() => {
                                                                      {
                                                                        const $t27886 = s.y;
                                                                        {
                                                                          const $t27888 = (() => {
                                                                            {
                                                                              const $t27887 = Math.sin(angle);
                                                                              return ($t27887 * r);
                                                                            }
                                                                          })();
                                                                          return ($t27886 + $t27888);
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27890 = { $: "AsteroidOrbiting", _0: idx, _1: angle };
                                                                      return ({ ...a, x: $t27885, y: $t27889, mode: $t27890 });
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              {
                                                                const $t27891 = ({ ...game, rng: rng2 });
                                                                {
                                                                  const $t27892 = { $: "Cons", _0: a2, _1: acc };
                                                                  return Perihelion$Combat$step_asteroids_go($t27891, rest, $t27892, dt_s);
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
                                                            const $t27893 = ({ ...game, rng: rng2 });
                                                            {
                                                              const $t27894 = { $: "Cons", _0: a2, _1: acc };
                                                              return Perihelion$Combat$step_asteroids_go($t27893, rest, $t27894, dt_s);
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
    const $t27911 = game.asteroids;
    {
      const $t27912 = { $: "Nil" };
      return Perihelion$Combat$step_asteroids_go(game, $t27911, $t27912, dt_s);
    }
  }
}
const Perihelion$Combat$step_asteroids$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_asteroids(game, dt_s) };

function Perihelion$Combat$step_ships(game, dt_s) {
  {
    const $t27913 = game.ships;
    {
      const $t27914 = { $: "Nil" };
      {
        const $t27915 = { $: "Nil" };
        return Perihelion$Combat$step_ships_go(game, $t27913, $t27914, $t27915, dt_s);
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
      const $f27926 = stars._0;
      const $f27927 = stars._1;
      {
        const rest = (() => {
          return $f27927;
        })();
        {
          const s = (() => {
            return $f27926;
          })();
          {
            const $t27916 = (i === skip_idx);
            if ($t27916 === true) {
              return (() => {
                {
                  const $t27917 = (i + 1);
                  return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $t27917, best, best_d);
                }
              })();
            } else {
              return (() => {
                {
                  const dx = (() => {
                    {
                      const $t27918 = s.x;
                      return ($t27918 - from_x);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27919 = s.y;
                        return ($t27919 - from_y);
                      }
                    })();
                    {
                      const d = (() => {
                        {
                          const $t27920 = (dx * dx);
                          {
                            const $t27921 = (dy * dy);
                            return ($t27920 + $t27921);
                          }
                        }
                      })();
                      {
                        const $t27922 = (d < best_d);
                        {
                          const $jp1018_$t27923 = (i + 1);
                          if ($t27922 === true) {
                            return (() => {
                              {
                                const $t27924 = { $: "Some", _0: i };
                                return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp1018_$t27923, $t27924, d);
                              }
                            })();
                          } else {
                            return (() => {
                              return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp1018_$t27923, best, best_d);
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
      const $f27942 = stars._0;
      const $f27943 = stars._1;
      {
        const rest = $f27943;
        {
          const s = $f27942;
          {
            const dx = (() => {
              {
                const $t27932 = s.x;
                return ($t27932 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27933 = s.y;
                  return ($t27933 - y);
                }
              })();
              {
                const $t27939 = (() => {
                  {
                    const $t27937 = (() => {
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
                      const $t27938 = s.capture_radius;
                      return ($t27937 <= $t27938);
                    }
                  }
                })();
                if ($t27939 === true) {
                  return (() => {
                    {
                      const $t27940 = { _0: i, _1: s };
                      return { $: "Some", _0: $t27940 };
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t27941 = (i + 1);
                      return Perihelion$Combat$arrived_star(rest, x, y, $t27941);
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
        const $t27948 = game.ball_x;
        return ($t27948 - sx);
      }
    })();
    {
      const dy = (() => {
        {
          const $t27949 = game.ball_y;
          return ($t27949 - sy);
        }
      })();
      {
        const dist = (() => {
          {
            const $t27952 = (() => {
              {
                const $t27950 = (dx * dx);
                {
                  const $t27951 = (dy * dy);
                  return ($t27950 + $t27951);
                }
              }
            })();
            return Math.sqrt($t27952);
          }
        })();
        {
          const $t27953 = (dist > 0.);
          if ($t27953 === true) {
            return (() => {
              {
                const $t27956 = (() => {
                  {
                    const $t27954 = (dx / dist);
                    return ($t27954 * 150.);
                  }
                })();
                {
                  const $t27959 = (() => {
                    {
                      const $t27957 = (dy / dist);
                      return ($t27957 * 150.);
                    }
                  })();
                  return ({ x: sx, y: sy, vx: $t27956, vy: $t27959, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
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
        const $t27963 = (() => {
          {
            const go_i4562 = { $: "$Clo_go$4775", _0: go$apply$4775 };
            {
              const $t274_i4563 = { $: "Nil" };
              return go$apply$4775(go_i4562, acc, $t274_i4563);
            }
          }
        })();
        {
          const $t27964 = game.enemy_shots;
          {
            const $t27965 = (() => {
              {
                const go_i4559 = { $: "$Clo_go$4773", _0: go$apply$4773 };
                {
                  const $t282_i4560 = (() => {
                    {
                      const go_i11915 = { $: "$Clo_go$5270", _0: go$apply$5270 };
                      {
                        const $t274_i11916 = { $: "Nil" };
                        return go$apply$5270(go_i11915, new_shots, $t274_i11916);
                      }
                    }
                  })();
                  return go$apply$4773(go_i4559, $t282_i4560, $t27964);
                }
              }
            })();
            return ({ ...game, ships: $t27963, enemy_shots: $t27965 });
          }
        }
      }
      break;
    }
    case "Cons": {
      const $f28076 = ships._0;
      const $f28077 = ships._1;
      {
        const rest = $f28077;
        {
          const sh = $f28076;
          {
            const $t27966 = sh.mode;
            switch ($t27966.$) {
              case "ShipOrbiting": {
                const $f28069 = $t27966._0;
                {
                  const angle = (() => {
                    return $f28069;
                  })();
                  {
                    const $t27968 = (() => {
                      {
                        const $t27967 = sh.star_idx;
                        return Perihelion$Core$star_at(game, $t27967);
                      }
                    })();
                    switch ($t27968.$) {
                      case "None": {
                        return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
                        break;
                      }
                      case "Some": {
                        const $f28034 = $t27968._0;
                        {
                          const s = $f28034;
                          {
                            const idle2 = (() => {
                              {
                                const $t27969 = sh.idle_timer;
                                return ($t27969 - dt_s);
                              }
                            })();
                            {
                              const $t27970 = (idle2 <= 0.);
                              if ($t27970 === true) {
                                return (() => {
                                  {
                                    const $p28005 = (() => {
                                      {
                                        const $t27971 = sh.hunter;
                                        if ($t27971 === true) {
                                          return (() => {
                                            {
                                              const $t27972 = game.ball_x;
                                              {
                                                const $t27973 = game.ball_y;
                                                return { _0: $t27972, _1: $t27973 };
                                              }
                                            }
                                          })();
                                        } else {
                                          return (() => {
                                            {
                                              const $t27974 = sh.x;
                                              {
                                                const $t27975 = sh.y;
                                                return { _0: $t27974, _1: $t27975 };
                                              }
                                            }
                                          })();
                                        }
                                      }
                                    })();
                                    {
                                      const tx = $p28005._0;
                                      {
                                        const ty = $p28005._1;
                                        {
                                          const $t27979 = (() => {
                                            {
                                              const $t27976 = sh.star_idx;
                                              {
                                                const $t27977 = game.stars;
                                                {
                                                  const $t27978 = { $: "None" };
                                                  return Perihelion$Combat$nearest_other_star(tx, ty, $t27976, $t27977, 0, $t27978, 999999999.);
                                                }
                                              }
                                            }
                                          })();
                                          switch ($t27979.$) {
                                            case "None": {
                                              {
                                                const sh2 = ({ ...sh, idle_timer: 6. });
                                                {
                                                  const $t27981 = { $: "Cons", _0: sh2, _1: acc };
                                                  return Perihelion$Combat$step_ships_go(game, rest, $t27981, new_shots, dt_s);
                                                }
                                              }
                                              break;
                                            }
                                            case "Some": {
                                              const $f28004 = $t27979._0;
                                              {
                                                const target_idx = $f28004;
                                                {
                                                  const $t27982 = Perihelion$Core$star_at(game, target_idx);
                                                  switch ($t27982.$) {
                                                    case "None": {
                                                      {
                                                        const sh2 = ({ ...sh, idle_timer: 6. });
                                                        {
                                                          const $t27984 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27984, new_shots, dt_s);
                                                        }
                                                      }
                                                      break;
                                                    }
                                                    case "Some": {
                                                      const $f28003 = $t27982._0;
                                                      {
                                                        const t = $f28003;
                                                        {
                                                          const dx = (() => {
                                                            {
                                                              const $t27985 = t.x;
                                                              {
                                                                const $t27986 = sh.x;
                                                                return ($t27985 - $t27986);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const dy = (() => {
                                                              {
                                                                const $t27987 = t.y;
                                                                {
                                                                  const $t27988 = sh.y;
                                                                  return ($t27987 - $t27988);
                                                                }
                                                              }
                                                            })();
                                                            {
                                                              const dist = (() => {
                                                                {
                                                                  const $t27991 = (() => {
                                                                    {
                                                                      const $t27989 = (dx * dx);
                                                                      {
                                                                        const $t27990 = (dy * dy);
                                                                        return ($t27989 + $t27990);
                                                                      }
                                                                    }
                                                                  })();
                                                                  return Math.sqrt($t27991);
                                                                }
                                                              })();
                                                              {
                                                                const vel = (() => {
                                                                  {
                                                                    const $t27992 = (dist > 0.);
                                                                    if ($t27992 === true) {
                                                                      return (() => {
                                                                        {
                                                                          const $t27995 = (() => {
                                                                            {
                                                                              const $t27993 = (dx / dist);
                                                                              return ($t27993 * 180.);
                                                                            }
                                                                          })();
                                                                          {
                                                                            const $t27998 = (() => {
                                                                              {
                                                                                const $t27996 = (dy / dist);
                                                                                return ($t27996 * 180.);
                                                                              }
                                                                            })();
                                                                            return { _0: $t27995, _1: $t27998 };
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
                                                                          const $t28000 = { $: "ShipFlying", _0: vx, _1: vy };
                                                                          return ({ ...sh, mode: $t28000 });
                                                                        }
                                                                      })();
                                                                      {
                                                                        const $t28001 = { $: "Cons", _0: sh2, _1: acc };
                                                                        return Perihelion$Combat$step_ships_go(game, rest, $t28001, new_shots, dt_s);
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
                                          const $t28010 = (() => {
                                            {
                                              const $t28009 = (d * 1.4);
                                              return ($t28009 * dt_s);
                                            }
                                          })();
                                          return (angle + $t28010);
                                        }
                                      })();
                                      {
                                        const r = (() => {
                                          {
                                            const $t28011 = s.capture_radius;
                                            return ($t28011 * 1.6);
                                          }
                                        })();
                                        {
                                          const sx = (() => {
                                            {
                                              const $t28013 = s.x;
                                              {
                                                const $t28015 = (() => {
                                                  {
                                                    const $t28014 = Math.cos(angle2);
                                                    return ($t28014 * r);
                                                  }
                                                })();
                                                return ($t28013 + $t28015);
                                              }
                                            }
                                          })();
                                          {
                                            const sy = (() => {
                                              {
                                                const $t28016 = s.y;
                                                {
                                                  const $t28018 = (() => {
                                                    {
                                                      const $t28017 = Math.sin(angle2);
                                                      return ($t28017 * r);
                                                    }
                                                  })();
                                                  return ($t28016 + $t28018);
                                                }
                                              }
                                            })();
                                            {
                                              const cd2 = (() => {
                                                {
                                                  const $t28019 = sh.fire_cooldown;
                                                  return ($t28019 - dt_s);
                                                }
                                              })();
                                              {
                                                const in_range = (() => {
                                                  {
                                                    const $t28022 = (() => {
                                                      {
                                                        const $t28020 = game.ball_x;
                                                        {
                                                          const $t28021 = game.ball_y;
                                                          {
                                                            const dx_i4570 = ($t28020 - sx);
                                                            {
                                                              const dy_i4571 = ($t28021 - sy);
                                                              {
                                                                const $t27625_i4572 = (dx_i4570 * dx_i4570);
                                                                {
                                                                  const $t27626_i4573 = (dy_i4571 * dy_i4571);
                                                                  return ($t27625_i4572 + $t27626_i4573);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const $t28025 = (380. * 380.);
                                                      return ($t28022 <= $t28025);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28027 = (() => {
                                                    {
                                                      const $t28026 = (cd2 <= 0.);
                                                      return ($t28026 && in_range);
                                                    }
                                                  })();
                                                  if ($t28027 === true) {
                                                    return (() => {
                                                      {
                                                        const shot = Perihelion$Combat$ship_fire_shot(sx, sy, game);
                                                        {
                                                          const sh2 = (() => {
                                                            {
                                                              const $t28028 = { $: "ShipOrbiting", _0: angle2 };
                                                              return ({ ...sh, x: sx, y: sy, mode: $t28028, idle_timer: idle2, fire_cooldown: 2.5 });
                                                            }
                                                          })();
                                                          {
                                                            const $t28030 = { $: "Cons", _0: sh2, _1: acc };
                                                            {
                                                              const $t28031 = { $: "Cons", _0: shot, _1: new_shots };
                                                              return Perihelion$Combat$step_ships_go(game, rest, $t28030, $t28031, dt_s);
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
                                                            const $t28032 = { $: "ShipOrbiting", _0: angle2 };
                                                            return ({ ...sh, x: sx, y: sy, mode: $t28032, idle_timer: idle2, fire_cooldown: cd2 });
                                                          }
                                                        })();
                                                        {
                                                          const $t28033 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t28033, new_shots, dt_s);
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
                const $f28070 = $t27966._0;
                const $f28071 = $t27966._1;
                {
                  const vy = (() => {
                    return $f28071;
                  })();
                  {
                    const vx = (() => {
                      return $f28070;
                    })();
                    {
                      const x2 = (() => {
                        {
                          const $t28035 = sh.x;
                          {
                            const $t28036 = (vx * dt_s);
                            return ($t28035 + $t28036);
                          }
                        }
                      })();
                      {
                        const y2 = (() => {
                          {
                            const $t28037 = sh.y;
                            {
                              const $t28038 = (vy * dt_s);
                              return ($t28037 + $t28038);
                            }
                          }
                        })();
                        {
                          const $t28040 = (() => {
                            {
                              const $t28039 = game.stars;
                              return Perihelion$Combat$arrived_star($t28039, x2, y2, 0);
                            }
                          })();
                          switch ($t28040.$) {
                            case "Some": {
                              const $f28068 = $t28040._0;
                              {
                                const pair = $f28068;
                                {
                                  const idx = pair._0;
                                  {
                                    const t = pair._1;
                                    {
                                      const angle = (() => {
                                        {
                                          const $t28042 = (() => {
                                            {
                                              const $t28041 = t.y;
                                              return (y2 - $t28041);
                                            }
                                          })();
                                          {
                                            const $t28044 = (() => {
                                              {
                                                const $t28043 = t.x;
                                                return (x2 - $t28043);
                                              }
                                            })();
                                            return Math.atan2($t28042, $t28044);
                                          }
                                        }
                                      })();
                                      {
                                        const $p28064 = (() => {
                                          {
                                            const $t28045 = game.rng;
                                            {
                                              const $p29281_i5129_i11918 = (() => {
                                                {
                                                  const $p15886_i12627 = (() => {
                                                    {
                                                      const $p15883_i1921_i12618 = Random$next_raw($t28045);
                                                      {
                                                        const hi_i1922_i12619 = $p15883_i1921_i12618._0;
                                                        {
                                                          const rng2_i1923_i12620 = $p15883_i1921_i12618._1;
                                                          {
                                                            const $p15882_i1924_i12621 = Random$next_raw(rng2_i1923_i12620);
                                                            {
                                                              const lo_i1925_i12622 = $p15882_i1924_i12621._0;
                                                              {
                                                                const rng3_i1926_i12623 = $p15882_i1924_i12621._1;
                                                                {
                                                                  const $t15881_i1930_i12626 = (() => {
                                                                    {
                                                                      const $t15880_i1929_i12625 = (() => {
                                                                        {
                                                                          const $t15878_i1927_i12624 = march_int_and(hi_i1922_i12619, 1048575);
                                                                          return ($t15878_i1927_i12624 * 4294967296);
                                                                        }
                                                                      })();
                                                                      return ($t15880_i1929_i12625 + lo_i1925_i12622);
                                                                    }
                                                                  })();
                                                                  return { _0: $t15881_i1930_i12626, _1: rng3_i1926_i12623 };
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const bits_i12628 = $p15886_i12627._0;
                                                    {
                                                      const rng2_i12629 = $p15886_i12627._1;
                                                      {
                                                        const $t15885_i12631 = (() => {
                                                          {
                                                            const $t15884_i12630 = bits_i12628;
                                                            return ($t15884_i12630 / 4.50359962737e+15);
                                                          }
                                                        })();
                                                        return { _0: $t15885_i12631, _1: rng2_i12629 };
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const t_i5130_i11919 = $p29281_i5129_i11918._0;
                                                {
                                                  const rng2_i5131_i11920 = $p29281_i5129_i11918._1;
                                                  {
                                                    const out_i5132_i11921 = { _0: rng2_i5131_i11920, _1: t_i5130_i11919 };
                                                    return out_i5132_i11921;
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const rng2 = $p28064._0;
                                          {
                                            const idle_f = $p28064._1;
                                            {
                                              const idle = (() => {
                                                {
                                                  const $t28050 = (() => {
                                                    {
                                                      const $t28049 = (6. - 3.);
                                                      return (idle_f * $t28049);
                                                    }
                                                  })();
                                                  return (3. + $t28050);
                                                }
                                              })();
                                              {
                                                const r = (() => {
                                                  {
                                                    const $t28051 = t.capture_radius;
                                                    return ($t28051 * 1.6);
                                                  }
                                                })();
                                                {
                                                  const sh2 = (() => {
                                                    {
                                                      const $t28056 = (() => {
                                                        {
                                                          const $t28053 = t.x;
                                                          {
                                                            const $t28055 = (() => {
                                                              {
                                                                const $t28054 = Math.cos(angle);
                                                                return ($t28054 * r);
                                                              }
                                                            })();
                                                            return ($t28053 + $t28055);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t28060 = (() => {
                                                          {
                                                            const $t28057 = t.y;
                                                            {
                                                              const $t28059 = (() => {
                                                                {
                                                                  const $t28058 = Math.sin(angle);
                                                                  return ($t28058 * r);
                                                                }
                                                              })();
                                                              return ($t28057 + $t28059);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t28061 = { $: "ShipOrbiting", _0: angle };
                                                          return ({ ...sh, x: $t28056, y: $t28060, star_idx: idx, mode: $t28061, idle_timer: idle });
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t28062 = ({ ...game, rng: rng2 });
                                                    {
                                                      const $t28063 = { $: "Cons", _0: sh2, _1: acc };
                                                      return Perihelion$Combat$step_ships_go($t28062, rest, $t28063, new_shots, dt_s);
                                                    }
                                                  }
                                                }
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
                                const $t28066 = Perihelion$Combat$in_band(game, x2, y2);
                                if ($t28066 === true) {
                                  return (() => {
                                    {
                                      const sh2 = ({ ...sh, x: x2, y: y2 });
                                      {
                                        const $t28067 = { $: "Cons", _0: sh2, _1: acc };
                                        return Perihelion$Combat$step_ships_go(game, rest, $t28067, new_shots, dt_s);
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
    const $t28082 = game.mode;
    switch ($t28082.$) {
      case "Orbiting": {
        const $f28103 = $t28082._0;
        const $f28104 = $t28082._1;
        const $f28105 = $t28082._2;
        {
          const idx = (() => {
            return $f28103;
          })();
          {
            const $t28083 = Perihelion$Core$star_at(game, idx);
            switch ($t28083.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f28095 = $t28083._0;
                {
                  const s = $f28095;
                  {
                    const rdx = (() => {
                      {
                        const $t28084 = game.ball_x;
                        {
                          const $t28085 = s.x;
                          return ($t28084 - $t28085);
                        }
                      }
                    })();
                    {
                      const rdy = (() => {
                        {
                          const $t28086 = game.ball_y;
                          {
                            const $t28087 = s.y;
                            return ($t28086 - $t28087);
                          }
                        }
                      })();
                      {
                        const rdist = (() => {
                          {
                            const $t28090 = (() => {
                              {
                                const $t28088 = (rdx * rdx);
                                {
                                  const $t28089 = (rdy * rdy);
                                  return ($t28088 + $t28089);
                                }
                              }
                            })();
                            return Math.sqrt($t28090);
                          }
                        })();
                        {
                          const $t28091 = (rdist > 0.);
                          if ($t28091 === true) {
                            return (() => {
                              {
                                const $t28092 = (rdx / rdist);
                                {
                                  const $t28093 = (rdy / rdist);
                                  {
                                    const $t28094 = { _0: $t28092, _1: $t28093 };
                                    return { $: "Some", _0: $t28094 };
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
        const $f28114 = $t28082._0;
        const $f28115 = $t28082._1;
        {
          const vy = (() => {
            return $f28115;
          })();
          {
            const vx = (() => {
              return $f28114;
            })();
            {
              const speed = (() => {
                {
                  const $t28098 = (() => {
                    {
                      const $t28096 = (vx * vx);
                      {
                        const $t28097 = (vy * vy);
                        return ($t28096 + $t28097);
                      }
                    }
                  })();
                  return Math.sqrt($t28098);
                }
              })();
              {
                const $t28099 = (speed > 0.);
                if ($t28099 === true) {
                  return (() => {
                    {
                      const $t28100 = (vx / speed);
                      {
                        const $t28101 = (vy / speed);
                        {
                          const $t28102 = { _0: $t28100, _1: $t28101 };
                          return { $: "Some", _0: $t28102 };
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
    const $t28120 = game.mode;
    switch ($t28120.$) {
      case "Orbiting": {
        const $f28128 = $t28120._0;
        const $f28129 = $t28120._1;
        const $f28130 = $t28120._2;
        return game;
        break;
      }
      case "Flying": {
        const $f28139 = $t28120._0;
        const $f28140 = $t28120._1;
        {
          const vy = (() => {
            return $f28140;
          })();
          {
            const vx = (() => {
              return $f28139;
            })();
            {
              const $t28127 = (() => {
                {
                  const $t28123 = (() => {
                    {
                      const $t28122 = (ax * 14.);
                      return (vx - $t28122);
                    }
                  })();
                  {
                    const $t28126 = (() => {
                      {
                        const $t28125 = (ay * 14.);
                        return (vy - $t28125);
                      }
                    })();
                    return { $: "Flying", _0: $t28123, _1: $t28126 };
                  }
                }
              })();
              return ({ ...game, mode: $t28127 });
            }
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
    const $p28186 = (() => {
      {
        const $t28166 = (0. - 0.5236);
        {
          const $t28159_i4686 = (() => {
            {
              const $t28156_i4683 = (() => {
                {
                  const $t28155_i4682 = Math.cos($t28166);
                  return (ax * $t28155_i4682);
                }
              })();
              {
                const $t28158_i4685 = (() => {
                  {
                    const $t28157_i4684 = Math.sin($t28166);
                    return (ay * $t28157_i4684);
                  }
                })();
                return ($t28156_i4683 - $t28158_i4685);
              }
            }
          })();
          {
            const $t28164_i4691 = (() => {
              {
                const $t28161_i4688 = (() => {
                  {
                    const $t28160_i4687 = Math.sin($t28166);
                    return (ax * $t28160_i4687);
                  }
                })();
                {
                  const $t28163_i4690 = (() => {
                    {
                      const $t28162_i4689 = Math.cos($t28166);
                      return (ay * $t28162_i4689);
                    }
                  })();
                  return ($t28161_i4688 + $t28163_i4690);
                }
              }
            })();
            return { _0: $t28159_i4686, _1: $t28164_i4691 };
          }
        }
      }
    })();
    {
      const a1x = $p28186._0;
      {
        const a1y = $p28186._1;
        {
          const $p28185 = (() => {
            {
              const $t28169 = (() => {
                {
                  const $t28168 = (0.5236 / 2.);
                  return (0. - $t28168);
                }
              })();
              {
                const $t28159_i4673 = (() => {
                  {
                    const $t28156_i4670 = (() => {
                      {
                        const $t28155_i4669 = Math.cos($t28169);
                        return (ax * $t28155_i4669);
                      }
                    })();
                    {
                      const $t28158_i4672 = (() => {
                        {
                          const $t28157_i4671 = Math.sin($t28169);
                          return (ay * $t28157_i4671);
                        }
                      })();
                      return ($t28156_i4670 - $t28158_i4672);
                    }
                  }
                })();
                {
                  const $t28164_i4678 = (() => {
                    {
                      const $t28161_i4675 = (() => {
                        {
                          const $t28160_i4674 = Math.sin($t28169);
                          return (ax * $t28160_i4674);
                        }
                      })();
                      {
                        const $t28163_i4677 = (() => {
                          {
                            const $t28162_i4676 = Math.cos($t28169);
                            return (ay * $t28162_i4676);
                          }
                        })();
                        return ($t28161_i4675 + $t28163_i4677);
                      }
                    }
                  })();
                  return { _0: $t28159_i4673, _1: $t28164_i4678 };
                }
              }
            }
          })();
          {
            const a2x = $p28185._0;
            {
              const a2y = $p28185._1;
              {
                const $p28184 = (() => {
                  {
                    const $t28171 = (0.5236 / 2.);
                    {
                      const $t28159_i4660 = (() => {
                        {
                          const $t28156_i4657 = (() => {
                            {
                              const $t28155_i4656 = Math.cos($t28171);
                              return (ax * $t28155_i4656);
                            }
                          })();
                          {
                            const $t28158_i4659 = (() => {
                              {
                                const $t28157_i4658 = Math.sin($t28171);
                                return (ay * $t28157_i4658);
                              }
                            })();
                            return ($t28156_i4657 - $t28158_i4659);
                          }
                        }
                      })();
                      {
                        const $t28164_i4665 = (() => {
                          {
                            const $t28161_i4662 = (() => {
                              {
                                const $t28160_i4661 = Math.sin($t28171);
                                return (ax * $t28160_i4661);
                              }
                            })();
                            {
                              const $t28163_i4664 = (() => {
                                {
                                  const $t28162_i4663 = Math.cos($t28171);
                                  return (ay * $t28162_i4663);
                                }
                              })();
                              return ($t28161_i4662 + $t28163_i4664);
                            }
                          }
                        })();
                        return { _0: $t28159_i4660, _1: $t28164_i4665 };
                      }
                    }
                  }
                })();
                {
                  const a3x = $p28184._0;
                  {
                    const a3y = $p28184._1;
                    {
                      const $p28183 = (() => {
                        {
                          const $t28159_i4647 = (() => {
                            {
                              const $t28156_i4644 = (() => {
                                {
                                  const $t28155_i4643 = Math.cos(0.5236);
                                  return (ax * $t28155_i4643);
                                }
                              })();
                              {
                                const $t28158_i4646 = (() => {
                                  {
                                    const $t28157_i4645 = Math.sin(0.5236);
                                    return (ay * $t28157_i4645);
                                  }
                                })();
                                return ($t28156_i4644 - $t28158_i4646);
                              }
                            }
                          })();
                          {
                            const $t28164_i4652 = (() => {
                              {
                                const $t28161_i4649 = (() => {
                                  {
                                    const $t28160_i4648 = Math.sin(0.5236);
                                    return (ax * $t28160_i4648);
                                  }
                                })();
                                {
                                  const $t28163_i4651 = (() => {
                                    {
                                      const $t28162_i4650 = Math.cos(0.5236);
                                      return (ay * $t28162_i4650);
                                    }
                                  })();
                                  return ($t28161_i4649 + $t28163_i4651);
                                }
                              }
                            })();
                            return { _0: $t28159_i4647, _1: $t28164_i4652 };
                          }
                        }
                      })();
                      {
                        const a4x = $p28183._0;
                        {
                          const a4y = $p28183._1;
                          {
                            const $t28173 = (() => {
                              {
                                const $t28146_i4636 = (ax * 420.);
                                {
                                  const $t28148_i4638 = (ay * 420.);
                                  return ({ x: x, y: y, vx: $t28146_i4636, vy: $t28148_i4638, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                }
                              }
                            })();
                            {
                              const $t28174 = (() => {
                                {
                                  const $t28146_i4627 = (a1x * 420.);
                                  {
                                    const $t28148_i4629 = (a1y * 420.);
                                    return ({ x: x, y: y, vx: $t28146_i4627, vy: $t28148_i4629, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                  }
                                }
                              })();
                              {
                                const $t28175 = (() => {
                                  {
                                    const $t28146_i4618 = (a2x * 420.);
                                    {
                                      const $t28148_i4620 = (a2y * 420.);
                                      return ({ x: x, y: y, vx: $t28146_i4618, vy: $t28148_i4620, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                    }
                                  }
                                })();
                                {
                                  const $t28176 = (() => {
                                    {
                                      const $t28146_i4609 = (a3x * 420.);
                                      {
                                        const $t28148_i4611 = (a3y * 420.);
                                        return ({ x: x, y: y, vx: $t28146_i4609, vy: $t28148_i4611, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                      }
                                    }
                                  })();
                                  {
                                    const $t28177 = (() => {
                                      {
                                        const $t28146_i4600 = (a4x * 420.);
                                        {
                                          const $t28148_i4602 = (a4y * 420.);
                                          return ({ x: x, y: y, vx: $t28146_i4600, vy: $t28148_i4602, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                        }
                                      }
                                    })();
                                    {
                                      const $t28178 = { $: "Nil" };
                                      {
                                        const $t28179 = { $: "Cons", _0: $t28177, _1: $t28178 };
                                        {
                                          const $t28180 = { $: "Cons", _0: $t28176, _1: $t28179 };
                                          {
                                            const $t28181 = { $: "Cons", _0: $t28175, _1: $t28180 };
                                            {
                                              const $t28182 = { $: "Cons", _0: $t28174, _1: $t28181 };
                                              return { $: "Cons", _0: $t28173, _1: $t28182 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t28187 = Perihelion$Core$active_weapon(game);
    switch ($t28187.$) {
      case "StarKiller": {
        {
          const $t28188 = game.starkiller_cooldown;
          return ($t28188 > 0.);
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
        const $t28190 = { $: "$Clo_$lam28189$3730", _0: $lam28189$apply$3730 };
        return List$any$List_String$Fn_String_Bool(keys, $t28190);
      }
    })();
    {
      const $t28196 = (() => {
        {
          const $t28194 = (() => {
            {
              const $t28191 = (!pressed);
              {
                const $t28193 = (() => {
                  {
                    const $t28192 = game.fire_cooldown;
                    return ($t28192 > 0.);
                  }
                })();
                return ($t28191 || $t28193);
              }
            }
          })();
          {
            const $t28195 = Perihelion$Combat$starkiller_on_cooldown(game);
            return ($t28194 || $t28195);
          }
        }
      })();
      if ($t28196 === true) {
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
                    const $t28197 = cy;
                    {
                      const $t28198 = game.camera_y;
                      return ($t28197 + $t28198);
                    }
                  }
                })();
                {
                  const dx = (() => {
                    {
                      const $t28199 = cx;
                      {
                        const $t28200 = game.ball_x;
                        return ($t28199 - $t28200);
                      }
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t28201 = game.ball_y;
                        return (cursor_world_y - $t28201);
                      }
                    })();
                    {
                      const dist = (() => {
                        {
                          const $t28204 = (() => {
                            {
                              const $t28202 = (dx * dx);
                              {
                                const $t28203 = (dy * dy);
                                return ($t28202 + $t28203);
                              }
                            }
                          })();
                          return Math.sqrt($t28204);
                        }
                      })();
                      {
                        const aim = (() => {
                          {
                            const $t28205 = (dist > 0.);
                            if ($t28205 === true) {
                              return (() => {
                                {
                                  const $t28206 = (dx / dist);
                                  {
                                    const $t28207 = (dy / dist);
                                    {
                                      const $t28208 = { _0: $t28206, _1: $t28207 };
                                      return { $: "Some", _0: $t28208 };
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
                            const $f28255 = aim._0;
                            {
                              const pair = $f28255;
                              {
                                const ax = pair._0;
                                {
                                  const ay = pair._1;
                                  {
                                    const g2 = Perihelion$Combat$apply_recoil(game, ax, ay);
                                    {
                                      const $t28209 = Perihelion$Core$active_weapon(game);
                                      {
                                        let new_shots;
                                        switch ($t28209.$) {
                                          case "Base": {
                                            new_shots = (() => {
                                              {
                                                const $t28212 = (() => {
                                                  {
                                                    const $t28210 = game.ball_x;
                                                    {
                                                      const $t28211 = game.ball_y;
                                                      {
                                                        const $t28146_i4713 = (ax * 420.);
                                                        {
                                                          const $t28148_i4715 = (ay * 420.);
                                                          return ({ x: $t28210, y: $t28211, vx: $t28146_i4713, vy: $t28148_i4715, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28213 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t28212, _1: $t28213 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Homing": {
                                            new_shots = (() => {
                                              {
                                                const $t28216 = (() => {
                                                  {
                                                    const $t28214 = game.ball_x;
                                                    {
                                                      const $t28215 = game.ball_y;
                                                      {
                                                        const $t28151_i4722 = (ax * 420.);
                                                        {
                                                          const $t28153_i4724 = (ay * 420.);
                                                          return ({ x: $t28214, y: $t28215, vx: $t28151_i4722, vy: $t28153_i4724, ttl: 3., homing: true, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28217 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t28216, _1: $t28217 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Spread": {
                                            new_shots = (() => {
                                              {
                                                const $t28218 = game.ball_x;
                                                {
                                                  const $t28219 = game.ball_y;
                                                  return Perihelion$Combat$spread_shots($t28218, $t28219, ax, ay);
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "StarKiller": {
                                            new_shots = (() => {
                                              {
                                                const $t28221 = (() => {
                                                  {
                                                    const $t28220 = Perihelion$Combat$starkiller_target_idx(game);
                                                    return Perihelion$Core$star_at(game, $t28220);
                                                  }
                                                })();
                                                switch ($t28221.$) {
                                                  case "None": {
                                                    return { $: "Nil" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f28244 = $t28221._0;
                                                    {
                                                      const target = $f28244;
                                                      {
                                                        const tdx = (() => {
                                                          {
                                                            const $t28222 = target.x;
                                                            {
                                                              const $t28223 = game.ball_x;
                                                              return ($t28222 - $t28223);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const tdy = (() => {
                                                            {
                                                              const $t28224 = target.y;
                                                              {
                                                                const $t28225 = game.ball_y;
                                                                return ($t28224 - $t28225);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const tdist = (() => {
                                                              {
                                                                const $t28228 = (() => {
                                                                  {
                                                                    const $t28226 = (tdx * tdx);
                                                                    {
                                                                      const $t28227 = (tdy * tdy);
                                                                      return ($t28226 + $t28227);
                                                                    }
                                                                  }
                                                                })();
                                                                return Math.sqrt($t28228);
                                                              }
                                                            })();
                                                            {
                                                              const $t28229 = (tdist <= 0.);
                                                              if ($t28229 === true) {
                                                                return { $: "Nil" };
                                                              } else {
                                                                return (() => {
                                                                  {
                                                                    const $t28242 = (() => {
                                                                      {
                                                                        const $t28230 = game.ball_x;
                                                                        {
                                                                          const $t28231 = game.ball_y;
                                                                          {
                                                                            const $t28234 = (() => {
                                                                              {
                                                                                const $t28232 = (tdx / tdist);
                                                                                return ($t28232 * 420.);
                                                                              }
                                                                            })();
                                                                            {
                                                                              const $t28237 = (() => {
                                                                                {
                                                                                  const $t28235 = (tdy / tdist);
                                                                                  return ($t28235 * 420.);
                                                                                }
                                                                              })();
                                                                              {
                                                                                const $t28239 = (3. * 3.);
                                                                                {
                                                                                  const $t28240 = target.x;
                                                                                  {
                                                                                    const $t28241 = target.y;
                                                                                    return ({ x: $t28230, y: $t28231, vx: $t28234, vy: $t28237, ttl: $t28239, homing: false, star_killer: true, target_x: $t28240, target_y: $t28241 });
                                                                                  }
                                                                                }
                                                                              }
                                                                            }
                                                                          }
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t28243 = { $: "Nil" };
                                                                      return { $: "Cons", _0: $t28242, _1: $t28243 };
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
                                              const $t28245 = Perihelion$Core$active_weapon(game);
                                              switch ($t28245.$) {
                                                case "StarKiller": {
                                                  return game.fire_cooldown;
                                                  break;
                                                }
                                                default: {
                                                  {
                                                    const reduced_i4704 = (() => {
                                                      {
                                                        const $t27614_i4703 = (() => {
                                                          {
                                                            const $t27612_i4701 = (() => {
                                                              {
                                                                const $t27611_i4700 = game.fire_rate_stacks;
                                                                return $t27611_i4700;
                                                              }
                                                            })();
                                                            return ($t27612_i4701 * 0.05);
                                                          }
                                                        })();
                                                        return (0.4 - $t27614_i4703);
                                                      }
                                                    })();
                                                    {
                                                      const $t27616_i4706 = (reduced_i4704 < 0.15);
                                                      if ($t27616_i4706 === true) {
                                                        return 0.15;
                                                      } else {
                                                        return reduced_i4704;
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
                                                const $t28248 = Perihelion$Core$active_weapon(game);
                                                switch ($t28248.$) {
                                                  case "StarKiller": {
                                                    {
                                                      let $t28249;
                                                      switch (new_shots.$) {
                                                        case "Nil": {
                                                          $t28249 = true;
                                                          break;
                                                        }
                                                        default: {
                                                          $t28249 = false;
                                                          break;
                                                        }
                                                      }
                                                      if ($t28249 === true) {
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
                                              const $t28252 = g2.player_shots;
                                              {
                                                const $t28253 = (() => {
                                                  {
                                                    const go_i4695 = { $: "$Clo_go$4773", _0: go$apply$4773 };
                                                    {
                                                      const $t282_i4696 = (() => {
                                                        {
                                                          const go_i11939 = { $: "$Clo_go$5270", _0: go$apply$5270 };
                                                          {
                                                            const $t274_i11940 = { $: "Nil" };
                                                            return go$apply$5270(go_i11939, $t28252, $t274_i11940);
                                                          }
                                                        }
                                                      })();
                                                      return go$apply$4773(go_i4695, $t282_i4696, new_shots);
                                                    }
                                                  }
                                                })();
                                                return ({ ...g2, player_shots: $t28253, fire_cooldown: cooldown2, starkiller_cooldown: starkiller_cd2 });
                                              }
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
      const $f28271 = stars._0;
      const $f28272 = stars._1;
      {
        const rest = (() => {
          return $f28272;
        })();
        {
          const s = (() => {
            return $f28271;
          })();
          {
            const $t28269 = (() => {
              {
                const $t28267 = s.x;
                {
                  const $t28268 = s.y;
                  {
                    const $t27627_i4744 = (() => {
                      {
                        const dx_i11945 = (tx - $t28267);
                        {
                          const dy_i11946 = (ty - $t28268);
                          {
                            const $t27625_i11947 = (dx_i11945 * dx_i11945);
                            {
                              const $t27626_i11948 = (dy_i11946 * dy_i11946);
                              return ($t27625_i11947 + $t27626_i11948);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27630_i4747 = (() => {
                        {
                          const $t27628_i4745 = (0.001 + 0.);
                          {
                            const $t27629_i4746 = (0.001 + 0.);
                            return ($t27628_i4745 * $t27629_i4746);
                          }
                        }
                      })();
                      return ($t27627_i4744 <= $t27630_i4747);
                    }
                  }
                }
              }
            })();
            if ($t28269 === true) {
              return { $: "Some", _0: i };
            } else {
              return (() => {
                {
                  const $t28270 = (i + 1);
                  return Perihelion$Combat$find_star_by_pos(rest, tx, ty, $t28270);
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
    const $t28277 = game.player_shots;
    {
      const $t28279 = { $: "$Clo_$lam28278$3736", _0: $lam28278$apply$3736 };
      {
        const sk_shots = (() => {
          {
            const pred_i4774 = $t28279;
            {
              const go_i4775 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4774 };
              {
                const $t323_i4776 = { $: "Nil" };
                return go$apply$4767(go_i4775, $t28277, $t323_i4776);
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
            const $f28303 = sk_shots._0;
            const $f28304 = sk_shots._1;
            {
              const s = $f28303;
              {
                const $t28285 = (() => {
                  {
                    const $t28280 = s.x;
                    {
                      const $t28281 = s.y;
                      {
                        const $t28283 = s.target_x;
                        {
                          const $t28284 = s.target_y;
                          {
                            const $t27627_i4769 = (() => {
                              {
                                const dx_i11961 = ($t28283 - $t28280);
                                {
                                  const dy_i11962 = ($t28284 - $t28281);
                                  {
                                    const $t27625_i11963 = (dx_i11961 * dx_i11961);
                                    {
                                      const $t27626_i11964 = (dy_i11962 * dy_i11962);
                                      return ($t27625_i11963 + $t27626_i11964);
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const $t27630_i4772 = (() => {
                                {
                                  const $t27628_i4770 = (20. + 0.);
                                  {
                                    const $t27629_i4771 = (20. + 0.);
                                    return ($t27628_i4770 * $t27629_i4771);
                                  }
                                }
                              })();
                              return ($t27627_i4769 <= $t27630_i4772);
                            }
                          }
                        }
                      }
                    }
                  }
                })();
                if ($t28285 === true) {
                  return (() => {
                    {
                      const $t28289 = (() => {
                        {
                          const $t28286 = game.stars;
                          {
                            const $t28287 = s.target_x;
                            {
                              const $t28288 = s.target_y;
                              return Perihelion$Combat$find_star_by_pos($t28286, $t28287, $t28288, 0);
                            }
                          }
                        }
                      })();
                      switch ($t28289.$) {
                        case "None": {
                          {
                            const $t28290 = game.player_shots;
                            {
                              const $t28293 = { $: "$Clo_$lam28291$3738", _0: $lam28291$apply$3738 };
                              {
                                const $t28294 = (() => {
                                  {
                                    const pred_i4751 = $t28293;
                                    {
                                      const go_i4752 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4751 };
                                      {
                                        const $t323_i4753 = { $: "Nil" };
                                        return go$apply$4767(go_i4752, $t28290, $t323_i4753);
                                      }
                                    }
                                  }
                                })();
                                return ({ ...game, player_shots: $t28294 });
                              }
                            }
                          }
                          break;
                        }
                        case "Some": {
                          const $f28302 = $t28289._0;
                          {
                            const tidx = $f28302;
                            {
                              const g2 = Perihelion$Core$remove_star(game, tidx);
                              {
                                const $t28295 = g2.ships;
                                {
                                  const $t28296 = (() => {
                                    {
                                      const $t28259_i4760 = { $: "$Clo_$lam28257$3733", _0: $lam28257$apply$3733, _1: tidx };
                                      {
                                        const $t28260_i4761 = (() => {
                                          {
                                            const pred_i11954 = $t28259_i4760;
                                            {
                                              const go_i11955 = { $: "$Clo_go$4779", _0: go$apply$4779, _1: pred_i11954 };
                                              {
                                                const $t323_i11956 = { $: "Nil" };
                                                return go$apply$4779(go_i11955, $t28295, $t323_i11956);
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const $t28266_i4762 = { $: "$Clo_$lam28261$3734", _0: $lam28261$apply$3734, _1: tidx };
                                          {
                                            const f_i11950 = $t28266_i4762;
                                            {
                                              const go_i11951 = { $: "$Clo_go$4777", _0: go$apply$4777, _1: f_i11950 };
                                              {
                                                const $t291_i11952 = { $: "Nil" };
                                                return go$apply$4777(go_i11951, $t28260_i4761, $t291_i11952);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28297 = game.player_shots;
                                    {
                                      const $t28300 = { $: "$Clo_$lam28298$3739", _0: $lam28298$apply$3739 };
                                      {
                                        const $t28301 = (() => {
                                          {
                                            const pred_i4755 = $t28300;
                                            {
                                              const go_i4756 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4755 };
                                              {
                                                const $t323_i4757 = { $: "Nil" };
                                                return go$apply$4767(go_i4756, $t28297, $t323_i4757);
                                              }
                                            }
                                          }
                                        })();
                                        return ({ ...g2, ships: $t28296, player_shots: $t28301 });
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
    const $p28341 = (() => {
      {
        const $t28316 = game.asteroids;
        {
          const $t28324 = { $: "$Clo_$lam28317$3741", _0: $lam28317$apply$3741, _1: game };
          {
            const pred_i4800 = $t28324;
            {
              const go_i4801 = { $: "$Clo_go$4786", _0: go$apply$4786, _1: pred_i4800 };
              {
                const $t578_i4802 = { $: "Nil" };
                {
                  const $t579_i4803 = { $: "Nil" };
                  return go$apply$4786(go_i4801, $t28316, $t578_i4802, $t579_i4803);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28341._0;
      {
        const alive = $p28341._1;
        {
          const $t28325 = game.player_shots;
          {
            const $t28334 = { $: "$Clo_$lam28326$3743", _0: $lam28326$apply$3743, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i4796 = $t28334;
                  {
                    const go_i4797 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4796 };
                    {
                      const $t323_i4798 = { $: "Nil" };
                      return go$apply$4767(go_i4797, $t28325, $t323_i4798);
                    }
                  }
                }
              })();
              {
                const $t28339 = (() => {
                  {
                    const $t28335 = game.score;
                    {
                      const $t28338 = (() => {
                        {
                          const $t28336 = (() => {
                            {
                              const go_i4794 = { $: "$Clo_go$4783", _0: go$apply$4783 };
                              return go$apply$4783(go_i4794, dead, 0);
                            }
                          })();
                          {
                            const $t28337 = game.multiplier;
                            return ($t28336 * $t28337);
                          }
                        }
                      })();
                      return ($t28335 + $t28338);
                    }
                  }
                })();
                {
                  const $t28340 = (() => {
                    {
                      const $t28315_i4792 = { $: "$Clo_$lam28312$3740", _0: $lam28312$apply$3740 };
                      {
                        const f_i11974 = $t28315_i4792;
                        {
                          const go_i11975 = { $: "$Clo_go$4781", _0: go$apply$4781, _1: f_i11974 };
                          {
                            const $t291_i11976 = { $: "Nil" };
                            return go$apply$4781(go_i11975, dead, $t291_i11976);
                          }
                        }
                      }
                    }
                  })();
                  return ({ ...game, asteroids: alive, player_shots: shots, score: $t28339, fx_bursts: $t28340 });
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

function Perihelion$Combat$collide_shots_ships(game) {
  {
    const $p28363 = (() => {
      {
        const $t28344 = game.ships;
        {
          const $t28349 = { $: "$Clo_$lam28345$3745", _0: $lam28345$apply$3745, _1: game };
          {
            const pred_i4822 = $t28349;
            {
              const go_i4823 = { $: "$Clo_go$4792", _0: go$apply$4792, _1: pred_i4822 };
              {
                const $t578_i4824 = { $: "Nil" };
                {
                  const $t579_i4825 = { $: "Nil" };
                  return go$apply$4792(go_i4823, $t28344, $t578_i4824, $t579_i4825);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28363._0;
      {
        const alive = $p28363._1;
        {
          const $t28350 = game.player_shots;
          {
            const $t28356 = { $: "$Clo_$lam28351$3747", _0: $lam28351$apply$3747, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i4818 = $t28356;
                  {
                    const go_i4819 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4818 };
                    {
                      const $t323_i4820 = { $: "Nil" };
                      return go$apply$4767(go_i4819, $t28350, $t323_i4820);
                    }
                  }
                }
              })();
              {
                const g2 = (() => {
                  {
                    const $t28362 = (() => {
                      {
                        const $t28357 = game.score;
                        {
                          const $t28361 = (() => {
                            {
                              const $t28359 = (() => {
                                {
                                  const $t28358 = (() => {
                                    {
                                      const go_i4816 = { $: "$Clo_go$4789", _0: go$apply$4789 };
                                      return go$apply$4789(go_i4816, dead, 0);
                                    }
                                  })();
                                  {
                                    const sr_s1 = ($t28358 + $t28358);
                                    return sr_s1;
                                  }
                                }
                              })();
                              {
                                const $t28360 = game.multiplier;
                                return ($t28359 * $t28360);
                              }
                            }
                          })();
                          return ($t28357 + $t28361);
                        }
                      }
                    })();
                    return ({ ...game, ships: alive, player_shots: shots, score: $t28362 });
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
      const $f28389 = dead._0;
      const $f28390 = dead._1;
      {
        const rest = $f28390;
        {
          const sh = $f28389;
          {
            const pos = (() => {
              {
                const pos_i4835 = (() => {
                  {
                    const $t27623_i4833 = sh.x;
                    {
                      const $t27624_i4834 = sh.y;
                      return { _0: $t27623_i4833, _1: $t27624_i4834 };
                    }
                  }
                })();
                return pos_i4835;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const $p28387 = (() => {
                    {
                      const $t28364 = game.rng;
                      {
                        const $p29281_i5129_i11983 = (() => {
                          {
                            const $p15886_i12657 = (() => {
                              {
                                const $p15883_i1921_i12648 = Random$next_raw($t28364);
                                {
                                  const hi_i1922_i12649 = $p15883_i1921_i12648._0;
                                  {
                                    const rng2_i1923_i12650 = $p15883_i1921_i12648._1;
                                    {
                                      const $p15882_i1924_i12651 = Random$next_raw(rng2_i1923_i12650);
                                      {
                                        const lo_i1925_i12652 = $p15882_i1924_i12651._0;
                                        {
                                          const rng3_i1926_i12653 = $p15882_i1924_i12651._1;
                                          {
                                            const $t15881_i1930_i12656 = (() => {
                                              {
                                                const $t15880_i1929_i12655 = (() => {
                                                  {
                                                    const $t15878_i1927_i12654 = march_int_and(hi_i1922_i12649, 1048575);
                                                    return ($t15878_i1927_i12654 * 4294967296);
                                                  }
                                                })();
                                                return ($t15880_i1929_i12655 + lo_i1925_i12652);
                                              }
                                            })();
                                            return { _0: $t15881_i1930_i12656, _1: rng3_i1926_i12653 };
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const bits_i12658 = $p15886_i12657._0;
                              {
                                const rng2_i12659 = $p15886_i12657._1;
                                {
                                  const $t15885_i12661 = (() => {
                                    {
                                      const $t15884_i12660 = bits_i12658;
                                      return ($t15884_i12660 / 4.50359962737e+15);
                                    }
                                  })();
                                  return { _0: $t15885_i12661, _1: rng2_i12659 };
                                }
                              }
                            }
                          }
                        })();
                        {
                          const t_i5130_i11984 = $p29281_i5129_i11983._0;
                          {
                            const rng2_i5131_i11985 = $p29281_i5129_i11983._1;
                            {
                              const out_i5132_i11986 = { _0: rng2_i5131_i11985, _1: t_i5130_i11984 };
                              return out_i5132_i11986;
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const rng2 = $p28387._0;
                    {
                      const roll = $p28387._1;
                      {
                        const g2 = (() => {
                          {
                            const $t28366 = (roll < 0.25);
                            if ($t28366 === true) {
                              return (() => {
                                {
                                  const owns_starkiller = (() => {
                                    {
                                      const $t28367 = game.owned_weapons;
                                      {
                                        const $t28368 = { $: "StarKiller" };
                                        {
                                          const $t690_i4830 = { $: "$Clo_$lam689$4794", _0: $lam689$apply$4794, _1: $t28368 };
                                          return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28367, $t690_i4830);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $p28386 = (() => {
                                      {
                                        const $p29281_i5129_i11978 = (() => {
                                          {
                                            const $p15886_i12642 = (() => {
                                              {
                                                const $p15883_i1921_i12633 = Random$next_raw(rng2);
                                                {
                                                  const hi_i1922_i12634 = $p15883_i1921_i12633._0;
                                                  {
                                                    const rng2_i1923_i12635 = $p15883_i1921_i12633._1;
                                                    {
                                                      const $p15882_i1924_i12636 = Random$next_raw(rng2_i1923_i12635);
                                                      {
                                                        const lo_i1925_i12637 = $p15882_i1924_i12636._0;
                                                        {
                                                          const rng3_i1926_i12638 = $p15882_i1924_i12636._1;
                                                          {
                                                            const $t15881_i1930_i12641 = (() => {
                                                              {
                                                                const $t15880_i1929_i12640 = (() => {
                                                                  {
                                                                    const $t15878_i1927_i12639 = march_int_and(hi_i1922_i12634, 1048575);
                                                                    return ($t15878_i1927_i12639 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15880_i1929_i12640 + lo_i1925_i12637);
                                                              }
                                                            })();
                                                            return { _0: $t15881_i1930_i12641, _1: rng3_i1926_i12638 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i12643 = $p15886_i12642._0;
                                              {
                                                const rng2_i12644 = $p15886_i12642._1;
                                                {
                                                  const $t15885_i12646 = (() => {
                                                    {
                                                      const $t15884_i12645 = bits_i12643;
                                                      return ($t15884_i12645 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15885_i12646, _1: rng2_i12644 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i5130_i11979 = $p29281_i5129_i11978._0;
                                          {
                                            const rng2_i5131_i11980 = $p29281_i5129_i11978._1;
                                            {
                                              const out_i5132_i11981 = { _0: rng2_i5131_i11980, _1: t_i5130_i11979 };
                                              return out_i5132_i11981;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const rng3 = $p28386._0;
                                      {
                                        const sk_roll = $p28386._1;
                                        {
                                          const $t28372 = (() => {
                                            {
                                              const $t28369 = (!owns_starkiller);
                                              {
                                                const $t28371 = (sk_roll < 0.08);
                                                return ($t28369 && $t28371);
                                              }
                                            }
                                          })();
                                          if ($t28372 === true) {
                                            return (() => {
                                              {
                                                const $t28376 = (() => {
                                                  {
                                                    const $t28375 = (() => {
                                                      {
                                                        const $t28374 = { $: "StarKiller" };
                                                        return { $: "OffenseWeapon", _0: $t28374 };
                                                      }
                                                    })();
                                                    return ({ x: sx, y: sy, ttl: 8., kind: $t28375 });
                                                  }
                                                })();
                                                {
                                                  const $t28377 = game.pickups;
                                                  {
                                                    const $t28378 = (() => {
                                                      return { $: "Cons", _0: $t28376, _1: $t28377 };
                                                    })();
                                                    return ({ ...game, rng: rng3, pickups: $t28378 });
                                                  }
                                                }
                                              }
                                            })();
                                          } else {
                                            return (() => {
                                              {
                                                const $p28385 = (() => {
                                                  {
                                                    const $t28379 = game.owned_weapons;
                                                    {
                                                      const $t28380 = game.special;
                                                      return Perihelion$Upgrades$roll_one(rng3, $t28379, $t28380);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const rng4 = $p28385._0;
                                                  {
                                                    const upgrade = $p28385._1;
                                                    {
                                                      const $t28382 = (() => {
                                                        return ({ x: sx, y: sy, ttl: 8., kind: upgrade });
                                                      })();
                                                      {
                                                        const $t28383 = game.pickups;
                                                        {
                                                          const $t28384 = (() => {
                                                            return { $: "Cons", _0: $t28382, _1: $t28383 };
                                                          })();
                                                          return ({ ...game, rng: rng4, pickups: $t28384 });
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
    const $t28404 = (() => {
      {
        const $t28401 = game.pickups;
        {
          const $t28403 = { $: "$Clo_$lam28402$3750", _0: $lam28402$apply$3750, _1: game };
          return List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool($t28401, $t28403);
        }
      }
    })();
    switch ($t28404.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28430 = $t28404._0;
        {
          const p = $f28430;
          {
            const $t28405 = game.pickups;
            {
              const $t28408 = { $: "$Clo_$lam28406$3751", _0: $lam28406$apply$3751, _1: game };
              {
                const remaining = (() => {
                  {
                    const pred_i4849 = $t28408;
                    {
                      const go_i4850 = { $: "$Clo_go$4763", _0: go$apply$4763, _1: pred_i4849 };
                      {
                        const $t323_i4851 = { $: "Nil" };
                        return go$apply$4763(go_i4850, $t28405, $t323_i4851);
                      }
                    }
                  }
                })();
                {
                  const $t28409 = p.kind;
                  switch ($t28409.$) {
                    case "SpecialItem": {
                      const $f28423 = $t28409._0;
                      {
                        const $jp_clo28425 = (() => {
                          return { $: "$Clo_$jp28424$3752", _0: $jp28424$apply$3752, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const $t28410 = game.special;
                          switch ($t28410.$) {
                            case "None": {
                              {
                                const $t28412 = (() => {
                                  {
                                    const $t28411 = p.kind;
                                    return Perihelion$Core$apply_upgrade(game, $t28411);
                                  }
                                })();
                                return ({ ...$t28412, pickups: remaining });
                              }
                              break;
                            }
                            case "Some": {
                              const $f28417 = $t28410._0;
                              {
                                const $t28413 = { $: "Milestone" };
                                {
                                  const $t28414 = p.kind;
                                  {
                                    const $t28415 = { $: "Nil" };
                                    {
                                      const $t28416 = (() => {
                                        return { $: "Cons", _0: $t28414, _1: $t28415 };
                                      })();
                                      return ({ ...game, pickups: remaining, phase: $t28413, milestone_choices: $t28416 });
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
                        const $jp_clo28429 = (() => {
                          return { $: "$Clo_$jp28428$3753", _0: $jp28428$apply$3753, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const grant = (() => {
                            {
                              const $t28418 = game.shield_reinforced;
                              if ($t28418 === true) {
                                return 2;
                              } else {
                                return 1;
                              }
                            }
                          })();
                          {
                            const $t28420 = (() => {
                              {
                                const $t28419 = game.shield;
                                return ($t28419 + grant);
                              }
                            })();
                            return ({ ...game, shield: $t28420, pickups: remaining });
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      {
                        const $t28422 = (() => {
                          {
                            const $t28421 = p.kind;
                            return Perihelion$Core$apply_upgrade(game, $t28421);
                          }
                        })();
                        return ({ ...$t28422, pickups: remaining });
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

function Perihelion$Combat$collide_ball_hazards(game) {
  {
    const shot_hit = (() => {
      {
        const $t28448 = game.enemy_shots;
        {
          const $t28450 = { $: "$Clo_$lam28449$3754", _0: $lam28449$apply$3754, _1: game };
          return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28448, $t28450);
        }
      }
    })();
    {
      const $t28452 = (() => {
        {
          const $t28451 = game.bullet_ward;
          return (shot_hit && $t28451);
        }
      })();
      if ($t28452 === true) {
        return (() => {
          {
            const $t28453 = game.enemy_shots;
            {
              const $t28456 = { $: "$Clo_$lam28454$3755", _0: $lam28454$apply$3755, _1: game };
              {
                const $t28457 = (() => {
                  {
                    const pred_i4891 = $t28456;
                    {
                      const go_i4892 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4891 };
                      {
                        const $t323_i4893 = { $: "Nil" };
                        return go$apply$4767(go_i4892, $t28453, $t323_i4893);
                      }
                    }
                  }
                })();
                return ({ ...game, bullet_ward: false, enemy_shots: $t28457 });
              }
            }
          }
        })();
      } else {
        return (() => {
          {
            const ast_hit = (() => {
              {
                const $t28458 = game.asteroids;
                {
                  const $t28460 = { $: "$Clo_$lam28459$3756", _0: $lam28459$apply$3756, _1: game };
                  return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28458, $t28460);
                }
              }
            })();
            {
              const ship_hit = (() => {
                {
                  const $t28461 = game.ships;
                  {
                    const $t28463 = { $: "$Clo_$lam28462$3757", _0: $lam28462$apply$3757, _1: game };
                    return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28461, $t28463);
                  }
                }
              })();
              {
                const $t28466 = (() => {
                  {
                    const $t28465 = (() => {
                      {
                        const $t28464 = (ast_hit || shot_hit);
                        return ($t28464 || ship_hit);
                      }
                    })();
                    return (!$t28465);
                  }
                })();
                if ($t28466 === true) {
                  return game;
                } else {
                  return (() => {
                    {
                      const $t28472 = (() => {
                        {
                          const $t28470 = (() => {
                            {
                              const $t28468 = (() => {
                                {
                                  const $t28467 = (!shot_hit);
                                  return (ast_hit && $t28467);
                                }
                              })();
                              {
                                const $t28469 = (!ship_hit);
                                return ($t28468 && $t28469);
                              }
                            }
                          })();
                          {
                            const $t28471 = game.deflector_plating;
                            return ($t28470 && $t28471);
                          }
                        }
                      })();
                      if ($t28472 === true) {
                        return (() => {
                          {
                            const $p28474 = (() => {
                              {
                                const $p28447_i4886 = (() => {
                                  {
                                    const $t28445_i4885 = game.rng;
                                    {
                                      const $p29281_i12677 = (() => {
                                        {
                                          const $p15886_i5123_i12672 = (() => {
                                            {
                                              const $p15883_i12064_i12663 = Random$next_raw($t28445_i4885);
                                              {
                                                const hi_i12065_i12664 = $p15883_i12064_i12663._0;
                                                {
                                                  const rng2_i12066_i12665 = $p15883_i12064_i12663._1;
                                                  {
                                                    const $p15882_i12067_i12666 = Random$next_raw(rng2_i12066_i12665);
                                                    {
                                                      const lo_i12068_i12667 = $p15882_i12067_i12666._0;
                                                      {
                                                        const rng3_i12069_i12668 = $p15882_i12067_i12666._1;
                                                        {
                                                          const $t15881_i12073_i12671 = (() => {
                                                            {
                                                              const $t15880_i12072_i12670 = (() => {
                                                                {
                                                                  const $t15878_i12070_i12669 = march_int_and(hi_i12065_i12664, 1048575);
                                                                  return ($t15878_i12070_i12669 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15880_i12072_i12670 + lo_i12068_i12667);
                                                            }
                                                          })();
                                                          return { _0: $t15881_i12073_i12671, _1: rng3_i12069_i12668 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i5124_i12673 = $p15886_i5123_i12672._0;
                                            {
                                              const rng2_i5125_i12674 = $p15886_i5123_i12672._1;
                                              {
                                                const $t15885_i5127_i12676 = (() => {
                                                  {
                                                    const $t15884_i5126_i12675 = bits_i5124_i12673;
                                                    return ($t15884_i5126_i12675 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15885_i5127_i12676, _1: rng2_i5125_i12674 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i12678 = $p29281_i12677._0;
                                        {
                                          const rng2_i12679 = $p29281_i12677._1;
                                          {
                                            const out_i12680 = { _0: rng2_i12679, _1: t_i12678 };
                                            return out_i12680;
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const rng2_i4887 = $p28447_i4886._0;
                                  {
                                    const t_i4888 = $p28447_i4886._1;
                                    {
                                      const $t28446_i4889 = (t_i4888 < 0.5);
                                      return { _0: rng2_i4887, _1: $t28446_i4889 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const rng2 = $p28474._0;
                              {
                                const deflected = $p28474._1;
                                if (deflected === true) {
                                  return ({ ...game, rng: rng2 });
                                } else {
                                  return (() => {
                                    {
                                      const $t28473 = ({ ...game, rng: rng2 });
                                      return Perihelion$Combat$collide_ball_hazards_shield_or_die($t28473);
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
    const $t28476 = (() => {
      {
        const $t28475 = game.shield;
        return ($t28475 > 0);
      }
    })();
    if ($t28476 === true) {
      return (() => {
        {
          const $t28477 = game.asteroids;
          {
            const $t28479 = { $: "$Clo_$lam28478$3758", _0: $lam28478$apply$3758, _1: game };
            {
              const dead_ast = (() => {
                {
                  const pred_i4913 = $t28479;
                  {
                    const go_i4914 = { $: "$Clo_go$4798", _0: go$apply$4798, _1: pred_i4913 };
                    {
                      const $t323_i4915 = { $: "Nil" };
                      return go$apply$4798(go_i4914, $t28477, $t323_i4915);
                    }
                  }
                }
              })();
              {
                const $t28481 = (() => {
                  {
                    const $t28480 = game.shield;
                    return ($t28480 - 1);
                  }
                })();
                {
                  const $t28482 = game.asteroids;
                  {
                    const $t28485 = { $: "$Clo_$lam28483$3759", _0: $lam28483$apply$3759, _1: game };
                    {
                      const $t28486 = (() => {
                        {
                          const pred_i4909 = $t28485;
                          {
                            const go_i4910 = { $: "$Clo_go$4798", _0: go$apply$4798, _1: pred_i4909 };
                            {
                              const $t323_i4911 = { $: "Nil" };
                              return go$apply$4798(go_i4910, $t28482, $t323_i4911);
                            }
                          }
                        }
                      })();
                      {
                        const $t28487 = game.enemy_shots;
                        {
                          const $t28490 = { $: "$Clo_$lam28488$3760", _0: $lam28488$apply$3760, _1: game };
                          {
                            const $t28491 = (() => {
                              {
                                const pred_i4905 = $t28490;
                                {
                                  const go_i4906 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: pred_i4905 };
                                  {
                                    const $t323_i4907 = { $: "Nil" };
                                    return go$apply$4767(go_i4906, $t28487, $t323_i4907);
                                  }
                                }
                              }
                            })();
                            {
                              const $t28492 = game.ships;
                              {
                                const $t28495 = { $: "$Clo_$lam28493$3761", _0: $lam28493$apply$3761, _1: game };
                                {
                                  const $t28496 = (() => {
                                    {
                                      const pred_i4901 = $t28495;
                                      {
                                        const go_i4902 = { $: "$Clo_go$4779", _0: go$apply$4779, _1: pred_i4901 };
                                        {
                                          const $t323_i4903 = { $: "Nil" };
                                          return go$apply$4779(go_i4902, $t28492, $t323_i4903);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28497 = game.fx_bursts;
                                    {
                                      const $t28498 = (() => {
                                        {
                                          const $t28315_i4899 = { $: "$Clo_$lam28312$3740", _0: $lam28312$apply$3740 };
                                          {
                                            const f_i11992 = $t28315_i4899;
                                            {
                                              const go_i11993 = { $: "$Clo_go$4781", _0: go$apply$4781, _1: f_i11992 };
                                              {
                                                const $t291_i11994 = { $: "Nil" };
                                                return go$apply$4781(go_i11993, dead_ast, $t291_i11994);
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const $t28499 = (() => {
                                          {
                                            const go_i4896 = { $: "$Clo_go$4796", _0: go$apply$4796 };
                                            {
                                              const $t282_i4897 = (() => {
                                                {
                                                  const go_i11989 = { $: "$Clo_go$4341", _0: go$apply$4341 };
                                                  {
                                                    const $t274_i11990 = { $: "Nil" };
                                                    return go$apply$4341(go_i11989, $t28497, $t274_i11990);
                                                  }
                                                }
                                              })();
                                              return go$apply$4796(go_i4896, $t282_i4897, $t28498);
                                            }
                                          }
                                        })();
                                        return ({ ...game, shield: $t28481, asteroids: $t28486, enemy_shots: $t28491, ships: $t28496, fx_bursts: $t28499 });
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
    const $t28500 = Perihelion$Core$star_at(game, star_idx);
    switch ($t28500.$) {
      case "None": {
        return ({ ...game, rng: rng });
        break;
      }
      case "Some": {
        const $f28521 = $t28500._0;
        {
          const s = $f28521;
          {
            const $p28520 = (() => {
              {
                const $p29281_i5129_i11996 = (() => {
                  {
                    const $p15886_i12691 = (() => {
                      {
                        const $p15883_i1921_i12682 = Random$next_raw(rng);
                        {
                          const hi_i1922_i12683 = $p15883_i1921_i12682._0;
                          {
                            const rng2_i1923_i12684 = $p15883_i1921_i12682._1;
                            {
                              const $p15882_i1924_i12685 = Random$next_raw(rng2_i1923_i12684);
                              {
                                const lo_i1925_i12686 = $p15882_i1924_i12685._0;
                                {
                                  const rng3_i1926_i12687 = $p15882_i1924_i12685._1;
                                  {
                                    const $t15881_i1930_i12690 = (() => {
                                      {
                                        const $t15880_i1929_i12689 = (() => {
                                          {
                                            const $t15878_i1927_i12688 = march_int_and(hi_i1922_i12683, 1048575);
                                            return ($t15878_i1927_i12688 * 4294967296);
                                          }
                                        })();
                                        return ($t15880_i1929_i12689 + lo_i1925_i12686);
                                      }
                                    })();
                                    return { _0: $t15881_i1930_i12690, _1: rng3_i1926_i12687 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i12692 = $p15886_i12691._0;
                      {
                        const rng2_i12693 = $p15886_i12691._1;
                        {
                          const $t15885_i12695 = (() => {
                            {
                              const $t15884_i12694 = bits_i12692;
                              return ($t15884_i12694 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15885_i12695, _1: rng2_i12693 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i5130_i11997 = $p29281_i5129_i11996._0;
                  {
                    const rng2_i5131_i11998 = $p29281_i5129_i11996._1;
                    {
                      const out_i5132_i11999 = { _0: rng2_i5131_i11998, _1: t_i5130_i11997 };
                      return out_i5132_i11999;
                    }
                  }
                }
              }
            })();
            {
              const rng2 = $p28520._0;
              {
                const idle_f = $p28520._1;
                {
                  const r = (() => {
                    {
                      const $t28501 = s.capture_radius;
                      return ($t28501 * 1.6);
                    }
                  })();
                  {
                    const idle = (() => {
                      {
                        const $t28507 = (() => {
                          {
                            const $t28506 = (6. - 3.);
                            return (idle_f * $t28506);
                          }
                        })();
                        return (3. + $t28507);
                      }
                    })();
                    {
                      const ship = (() => {
                        {
                          const $t28511 = (() => {
                            {
                              const $t28508 = s.x;
                              {
                                const $t28510 = (() => {
                                  {
                                    const $t28509 = Math.cos(0.);
                                    return ($t28509 * r);
                                  }
                                })();
                                return ($t28508 + $t28510);
                              }
                            }
                          })();
                          {
                            const $t28515 = (() => {
                              {
                                const $t28512 = s.y;
                                {
                                  const $t28514 = (() => {
                                    {
                                      const $t28513 = Math.sin(0.);
                                      return ($t28513 * r);
                                    }
                                  })();
                                  return ($t28512 + $t28514);
                                }
                              }
                            })();
                            {
                              const $t28516 = { $: "ShipOrbiting", _0: 0. };
                              return ({ star_idx: star_idx, x: $t28511, y: $t28515, mode: $t28516, fire_cooldown: 2.5, idle_timer: idle, hunter: false });
                            }
                          }
                        }
                      })();
                      {
                        const $t28518 = game.ships;
                        {
                          const $t28519 = (() => {
                            return { $: "Cons", _0: ship, _1: $t28518 };
                          })();
                          return ({ ...game, rng: rng2, ships: $t28519 });
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
        const $t28523 = (() => {
          {
            const $t28522 = game.current;
            return ($t28522 > 0);
          }
        })();
        if ($t28523 === true) {
          return (() => {
            {
              const $t28524 = game.current;
              return ($t28524 - 1);
            }
          })();
        } else {
          return 0;
        }
      }
    })();
    {
      const $t28525 = Perihelion$Core$star_at(game, idx);
      switch ($t28525.$) {
        case "None": {
          return ({ ...game, rng: rng });
          break;
        }
        case "Some": {
          const $f28546 = $t28525._0;
          {
            const s = $f28546;
            {
              const $p28545 = (() => {
                {
                  const $p29281_i5129_i12001 = (() => {
                    {
                      const $p15886_i12706 = (() => {
                        {
                          const $p15883_i1921_i12697 = Random$next_raw(rng);
                          {
                            const hi_i1922_i12698 = $p15883_i1921_i12697._0;
                            {
                              const rng2_i1923_i12699 = $p15883_i1921_i12697._1;
                              {
                                const $p15882_i1924_i12700 = Random$next_raw(rng2_i1923_i12699);
                                {
                                  const lo_i1925_i12701 = $p15882_i1924_i12700._0;
                                  {
                                    const rng3_i1926_i12702 = $p15882_i1924_i12700._1;
                                    {
                                      const $t15881_i1930_i12705 = (() => {
                                        {
                                          const $t15880_i1929_i12704 = (() => {
                                            {
                                              const $t15878_i1927_i12703 = march_int_and(hi_i1922_i12698, 1048575);
                                              return ($t15878_i1927_i12703 * 4294967296);
                                            }
                                          })();
                                          return ($t15880_i1929_i12704 + lo_i1925_i12701);
                                        }
                                      })();
                                      return { _0: $t15881_i1930_i12705, _1: rng3_i1926_i12702 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i12707 = $p15886_i12706._0;
                        {
                          const rng2_i12708 = $p15886_i12706._1;
                          {
                            const $t15885_i12710 = (() => {
                              {
                                const $t15884_i12709 = bits_i12707;
                                return ($t15884_i12709 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15885_i12710, _1: rng2_i12708 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i5130_i12002 = $p29281_i5129_i12001._0;
                    {
                      const rng2_i5131_i12003 = $p29281_i5129_i12001._1;
                      {
                        const out_i5132_i12004 = { _0: rng2_i5131_i12003, _1: t_i5130_i12002 };
                        return out_i5132_i12004;
                      }
                    }
                  }
                }
              })();
              {
                const rng2 = $p28545._0;
                {
                  const idle_f = $p28545._1;
                  {
                    const r = (() => {
                      {
                        const $t28526 = s.capture_radius;
                        return ($t28526 * 1.6);
                      }
                    })();
                    {
                      const idle = (() => {
                        {
                          const $t28532 = (() => {
                            {
                              const $t28531 = (6. - 3.);
                              return (idle_f * $t28531);
                            }
                          })();
                          return (3. + $t28532);
                        }
                      })();
                      {
                        const ship = (() => {
                          {
                            const $t28536 = (() => {
                              {
                                const $t28533 = s.x;
                                {
                                  const $t28535 = (() => {
                                    {
                                      const $t28534 = Math.cos(0.);
                                      return ($t28534 * r);
                                    }
                                  })();
                                  return ($t28533 + $t28535);
                                }
                              }
                            })();
                            {
                              const $t28540 = (() => {
                                {
                                  const $t28537 = s.y;
                                  {
                                    const $t28539 = (() => {
                                      {
                                        const $t28538 = Math.sin(0.);
                                        return ($t28538 * r);
                                      }
                                    })();
                                    return ($t28537 + $t28539);
                                  }
                                }
                              })();
                              {
                                const $t28541 = { $: "ShipOrbiting", _0: 0. };
                                return ({ star_idx: idx, x: $t28536, y: $t28540, mode: $t28541, fire_cooldown: 2.5, idle_timer: idle, hunter: true });
                              }
                            }
                          }
                        })();
                        {
                          const $t28543 = game.ships;
                          {
                            const $t28544 = (() => {
                              return { $: "Cons", _0: ship, _1: $t28543 };
                            })();
                            return ({ ...game, rng: rng2, ships: $t28544 });
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
    const $t28549 = (() => {
      {
        const $t28547 = game.score;
        return ($t28547 < 4);
      }
    })();
    if ($t28549 === true) {
      return game;
    } else {
      return (() => {
        {
          const $p28561 = (() => {
            {
              const $t28550 = game.rng;
              {
                const $p29281_i5129_i12011 = (() => {
                  {
                    const $p15886_i12736 = (() => {
                      {
                        const $p15883_i1921_i12727 = Random$next_raw($t28550);
                        {
                          const hi_i1922_i12728 = $p15883_i1921_i12727._0;
                          {
                            const rng2_i1923_i12729 = $p15883_i1921_i12727._1;
                            {
                              const $p15882_i1924_i12730 = Random$next_raw(rng2_i1923_i12729);
                              {
                                const lo_i1925_i12731 = $p15882_i1924_i12730._0;
                                {
                                  const rng3_i1926_i12732 = $p15882_i1924_i12730._1;
                                  {
                                    const $t15881_i1930_i12735 = (() => {
                                      {
                                        const $t15880_i1929_i12734 = (() => {
                                          {
                                            const $t15878_i1927_i12733 = march_int_and(hi_i1922_i12728, 1048575);
                                            return ($t15878_i1927_i12733 * 4294967296);
                                          }
                                        })();
                                        return ($t15880_i1929_i12734 + lo_i1925_i12731);
                                      }
                                    })();
                                    return { _0: $t15881_i1930_i12735, _1: rng3_i1926_i12732 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i12737 = $p15886_i12736._0;
                      {
                        const rng2_i12738 = $p15886_i12736._1;
                        {
                          const $t15885_i12740 = (() => {
                            {
                              const $t15884_i12739 = bits_i12737;
                              return ($t15884_i12739 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15885_i12740, _1: rng2_i12738 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i5130_i12012 = $p29281_i5129_i12011._0;
                  {
                    const rng2_i5131_i12013 = $p29281_i5129_i12011._1;
                    {
                      const out_i5132_i12014 = { _0: rng2_i5131_i12013, _1: t_i5130_i12012 };
                      return out_i5132_i12014;
                    }
                  }
                }
              }
            }
          })();
          {
            const rng2 = $p28561._0;
            {
              const roll = $p28561._1;
              {
                const chance_raw = (() => {
                  {
                    const $t28555 = (() => {
                      {
                        const $t28554 = (() => {
                          {
                            const $t28553 = (() => {
                              {
                                const $t28551 = game.score;
                                return ($t28551 - 4);
                              }
                            })();
                            return $t28553;
                          }
                        })();
                        return (0.04 * $t28554);
                      }
                    })();
                    return (0.16 + $t28555);
                  }
                })();
                {
                  const chance = (() => {
                    {
                      const $t28556 = (chance_raw > 0.45);
                      if ($t28556 === true) {
                        return 0.45;
                      } else {
                        return chance_raw;
                      }
                    }
                  })();
                  {
                    const $t28557 = (roll < chance);
                    if ($t28557 === true) {
                      return (() => {
                        {
                          const $p28560 = (() => {
                            {
                              const $p29281_i5129_i12006 = (() => {
                                {
                                  const $p15886_i12721 = (() => {
                                    {
                                      const $p15883_i1921_i12712 = Random$next_raw(rng2);
                                      {
                                        const hi_i1922_i12713 = $p15883_i1921_i12712._0;
                                        {
                                          const rng2_i1923_i12714 = $p15883_i1921_i12712._1;
                                          {
                                            const $p15882_i1924_i12715 = Random$next_raw(rng2_i1923_i12714);
                                            {
                                              const lo_i1925_i12716 = $p15882_i1924_i12715._0;
                                              {
                                                const rng3_i1926_i12717 = $p15882_i1924_i12715._1;
                                                {
                                                  const $t15881_i1930_i12720 = (() => {
                                                    {
                                                      const $t15880_i1929_i12719 = (() => {
                                                        {
                                                          const $t15878_i1927_i12718 = march_int_and(hi_i1922_i12713, 1048575);
                                                          return ($t15878_i1927_i12718 * 4294967296);
                                                        }
                                                      })();
                                                      return ($t15880_i1929_i12719 + lo_i1925_i12716);
                                                    }
                                                  })();
                                                  return { _0: $t15881_i1930_i12720, _1: rng3_i1926_i12717 };
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const bits_i12722 = $p15886_i12721._0;
                                    {
                                      const rng2_i12723 = $p15886_i12721._1;
                                      {
                                        const $t15885_i12725 = (() => {
                                          {
                                            const $t15884_i12724 = bits_i12722;
                                            return ($t15884_i12724 / 4.50359962737e+15);
                                          }
                                        })();
                                        return { _0: $t15885_i12725, _1: rng2_i12723 };
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const t_i5130_i12007 = $p29281_i5129_i12006._0;
                                {
                                  const rng2_i5131_i12008 = $p29281_i5129_i12006._1;
                                  {
                                    const out_i5132_i12009 = { _0: rng2_i5131_i12008, _1: t_i5130_i12007 };
                                    return out_i5132_i12009;
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const rng3 = $p28560._0;
                            {
                              const kind_roll = $p28560._1;
                              {
                                const $t28559 = (kind_roll < 0.5);
                                if ($t28559 === true) {
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
    const $t28562 = game.stars;
    return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int($t28562, i);
  }
}
const Perihelion$Core$star_at$clo = { _0: ($_, game, i) => Perihelion$Core$star_at(game, i) };

function Perihelion$Core$remove_at(xs, idx) {
  {
    const $t28563 = (() => {
      {
        const go_i4932 = { $: "$Clo_go$4804", _0: go$apply$4804 };
        {
          const $t529_i4933 = { $: "Nil" };
          return go$apply$4804(go_i4932, xs, idx, $t529_i4933);
        }
      }
    })();
    {
      const $t28564 = (idx + 1);
      {
        const $t28565 = List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, $t28564);
        {
          const go_i4928 = { $: "$Clo_go$4801", _0: go$apply$4801 };
          {
            const $t282_i4929 = (() => {
              {
                const go_i12016 = { $: "$Clo_go$5273", _0: go$apply$5273 };
                {
                  const $t274_i12017 = { $: "Nil" };
                  return go$apply$5273(go_i12016, $t28563, $t274_i12017);
                }
              }
            })();
            return go$apply$4801(go_i4928, $t282_i4929, $t28565);
          }
        }
      }
    }
  }
}
const Perihelion$Core$remove_at$clo = { _0: ($_, xs, idx) => Perihelion$Core$remove_at(xs, idx) };

function Perihelion$Core$remove_star(game, idx) {
  {
    const $t28566 = game.stars;
    {
      const $t28567 = (() => {
        return Perihelion$Core$remove_at($t28566, idx);
      })();
      return ({ ...game, stars: $t28567 });
    }
  }
}
const Perihelion$Core$remove_star$clo = { _0: ($_, game, idx) => Perihelion$Core$remove_star(game, idx) };

function Perihelion$Core$ring_count(s) {
  {
    const $t28568 = s.orbits;
    {
      const go_i4935 = { $: "$Clo_go$4806", _0: go$apply$4806 };
      return go$apply$4806(go_i4935, $t28568, 0);
    }
  }
}
const Perihelion$Core$ring_count$clo = { _0: ($_, s) => Perihelion$Core$ring_count(s) };

function Perihelion$Core$ring_at(s, i) {
  {
    const $t28570 = (() => {
      {
        const $t28569 = s.orbits;
        return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int($t28569, i);
      }
    })();
    switch ($t28570.$) {
      case "Some": {
        const $f28573 = $t28570._0;
        {
          const o = $f28573;
          return o;
        }
        break;
      }
      case "None": {
        {
          const $t28571 = s.capture_radius;
          {
            const $t28572 = s.speed_mult;
            return ({ radius: $t28571, speed_mult: $t28572 });
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
        const $t28578 = { $: "$Clo_$lam28575$3762", _0: $lam28575$apply$3762 };
        return List$any$List_String$Fn_String_Bool(keys, $t28578);
      }
    })();
    {
      const inn = (() => {
        {
          const $t28582 = { $: "$Clo_$lam28579$3763", _0: $lam28579$apply$3763 };
          return List$any$List_String$Fn_String_Bool(keys, $t28582);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28583;
            if (out === true) {
              $t28583 = 1;
            } else {
              $t28583 = 0;
            }
            {
              let $t28584;
              if (inn === true) {
                $t28584 = 1;
              } else {
                $t28584 = 0;
              }
              return ($t28583 - $t28584);
            }
          }
        })();
        {
          const target = (ring_idx + delta);
          {
            const $t28585 = (target < 0);
            if ($t28585 === true) {
              return 0;
            } else {
              return (() => {
                {
                  const $t28587 = (() => {
                    {
                      const $t28586 = (n - 1);
                      return (target > $t28586);
                    }
                  })();
                  if ($t28587 === true) {
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
        const $t28588 = game.owned_weapons;
        {
          const go_i4939 = { $: "$Clo_go$4810", _0: go$apply$4810 };
          return go$apply$4810(go_i4939, $t28588, 0);
        }
      }
    })();
    {
      const idx = (() => {
        {
          const $t28590 = (() => {
            {
              const $t28589 = game.active_weapon_idx;
              return ($t28589 >= n);
            }
          })();
          if ($t28590 === true) {
            return 0;
          } else {
            return game.active_weapon_idx;
          }
        }
      })();
      {
        const $t28592 = (() => {
          {
            const $t28591 = game.owned_weapons;
            return List$nth_opt$List_WeaponKind$Int($t28591, idx);
          }
        })();
        switch ($t28592.$) {
          case "Some": {
            const $f28593 = $t28592._0;
            {
              const w = $f28593;
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
        const $t28597 = { $: "$Clo_$lam28594$3764", _0: $lam28594$apply$3764 };
        return List$any$List_String$Fn_String_Bool(keys, $t28597);
      }
    })();
    {
      const prev = (() => {
        {
          const $t28601 = { $: "$Clo_$lam28598$3765", _0: $lam28598$apply$3765 };
          return List$any$List_String$Fn_String_Bool(keys, $t28601);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28602;
            if (next === true) {
              $t28602 = 1;
            } else {
              $t28602 = 0;
            }
            {
              let $t28603;
              if (prev === true) {
                $t28603 = 1;
              } else {
                $t28603 = 0;
              }
              return ($t28602 - $t28603);
            }
          }
        })();
        {
          const raw = (() => {
            {
              const $t28604 = (idx + delta);
              return march_int_mod($t28604, n);
            }
          })();
          {
            const $t28605 = (raw < 0);
            if ($t28605 === true) {
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
        const $t28609 = { $: "$Clo_$lam28606$3766", _0: $lam28606$apply$3766 };
        return List$any$List_String$Fn_String_Bool(keys, $t28609);
      }
    })();
    {
      const up = (() => {
        {
          const $t28613 = { $: "$Clo_$lam28610$3767", _0: $lam28610$apply$3767 };
          return List$any$List_String$Fn_String_Bool(keys, $t28613);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28614;
            if (dn === true) {
              $t28614 = 1;
            } else {
              $t28614 = 0;
            }
            {
              let $t28615;
              if (up === true) {
                $t28615 = 1;
              } else {
                $t28615 = 0;
              }
              return ($t28614 - $t28615);
            }
          }
        })();
        {
          const $t28617 = (() => {
            {
              const $t28616 = (offset + delta);
              return ($t28616 + 3);
            }
          })();
          return march_int_mod($t28617, 3);
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
            const $t28620 = best.x;
            {
              const $t28621 = game.ball_x;
              return ($t28620 - $t28621);
            }
          }
        })();
        {
          const dy = (() => {
            {
              const $t28622 = best.y;
              {
                const $t28623 = game.ball_y;
                return ($t28622 - $t28623);
              }
            }
          })();
          {
            const d = Math.sqrt(best_d2);
            {
              const $t28624 = (d > 0.);
              if ($t28624 === true) {
                return (() => {
                  {
                    const $t28625 = (dx / d);
                    {
                      const $t28626 = (dy / d);
                      {
                        const $t28627 = { _0: $t28625, _1: $t28626 };
                        return { $: "Some", _0: $t28627 };
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
      const $f28633 = stars._0;
      const $f28634 = stars._1;
      {
        const rest = (() => {
          return $f28634;
        })();
        {
          const s = (() => {
            return $f28633;
          })();
          {
            const d2 = (() => {
              {
                const $t28628 = game.ball_x;
                {
                  const $t28629 = game.ball_y;
                  {
                    const $t28630 = s.x;
                    {
                      const $t28631 = s.y;
                      {
                        const dx_i4946 = ($t28628 - $t28630);
                        {
                          const dy_i4947 = ($t28629 - $t28631);
                          {
                            const $t28618_i4948 = (dx_i4946 * dx_i4946);
                            {
                              const $t28619_i4949 = (dy_i4947 * dy_i4947);
                              return ($t28618_i4948 + $t28619_i4949);
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
              const $t28632 = (d2 < best_d2);
              if ($t28632 === true) {
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
    const $t28639 = game.stars;
    switch ($t28639.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f28645 = $t28639._0;
        const $f28646 = $t28639._1;
        {
          const rest = (() => {
            return $f28646;
          })();
          {
            const s0 = (() => {
              return $f28645;
            })();
            {
              const $t28644 = (() => {
                {
                  const $t28640 = game.ball_x;
                  {
                    const $t28641 = game.ball_y;
                    {
                      const $t28642 = s0.x;
                      {
                        const $t28643 = s0.y;
                        {
                          const dx_i4955 = ($t28640 - $t28642);
                          {
                            const dy_i4956 = ($t28641 - $t28643);
                            {
                              const $t28618_i4957 = (dx_i4955 * dx_i4955);
                              {
                                const $t28619_i4958 = (dy_i4956 * dy_i4956);
                                return ($t28618_i4957 + $t28619_i4958);
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
                const $rc_617 = Perihelion$Core$nearest_star_dir_go(game, rest, s0, $t28644);
                return $rc_617;
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
    const $p28662 = (() => {
      {
        const $t28651 = game.rng;
        {
          const $p29281_i12024 = (() => {
            {
              const $p15886_i5123_i12019 = (() => {
                {
                  const $p15883_i12742 = Random$next_raw($t28651);
                  {
                    const hi_i12743 = $p15883_i12742._0;
                    {
                      const rng2_i12744 = $p15883_i12742._1;
                      {
                        const $p15882_i12745 = Random$next_raw(rng2_i12744);
                        {
                          const lo_i12746 = $p15882_i12745._0;
                          {
                            const rng3_i12747 = $p15882_i12745._1;
                            {
                              const $t15881_i12750 = (() => {
                                {
                                  const $t15880_i12749 = (() => {
                                    {
                                      const $t15878_i12748 = march_int_and(hi_i12743, 1048575);
                                      return ($t15878_i12748 * 4294967296);
                                    }
                                  })();
                                  return ($t15880_i12749 + lo_i12746);
                                }
                              })();
                              return { _0: $t15881_i12750, _1: rng3_i12747 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i5124_i12020 = $p15886_i5123_i12019._0;
                {
                  const rng2_i5125_i12021 = $p15886_i5123_i12019._1;
                  {
                    const $t15885_i5127_i12023 = (() => {
                      {
                        const $t15884_i5126_i12022 = bits_i5124_i12020;
                        return ($t15884_i5126_i12022 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15885_i5127_i12023, _1: rng2_i5125_i12021 };
                  }
                }
              }
            }
          })();
          {
            const t_i12025 = $p29281_i12024._0;
            {
              const rng2_i12026 = $p29281_i12024._1;
              {
                const out_i12027 = { _0: rng2_i12026, _1: t_i12025 };
                return out_i12027;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28662._0;
      {
        const t = $p28662._1;
        {
          const jump = (() => {
            {
              const $t28655 = (() => {
                {
                  const $t28654 = (t * 4.);
                  return Math.trunc($t28654);
                }
              })();
              return (1 + $t28655);
            }
          })();
          {
            const target_idx = (() => {
              {
                const $t28656 = game.current;
                return ($t28656 + jump);
              }
            })();
            {
              const $t28657 = Perihelion$Core$star_at(game, target_idx);
              switch ($t28657.$) {
                case "None": {
                  return ({ ...game, rng: rng2 });
                  break;
                }
                case "Some": {
                  const $f28661 = $t28657._0;
                  {
                    const target = $f28661;
                    {
                      const $t28660 = (() => {
                        {
                          const $t28659 = (() => {
                            {
                              const $t28658 = game.special_charges;
                              return ($t28658 - 1);
                            }
                          })();
                          return ({ ...game, rng: rng2, special_charges: $t28659 });
                        }
                      })();
                      return Perihelion$Core$on_capture($t28660, target, target_idx);
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
        const $t28666 = { $: "$Clo_$lam28663$3770", _0: $lam28663$apply$3770 };
        return List$any$List_String$Fn_String_Bool(keys, $t28666);
      }
    })();
    {
      const $t28670 = (() => {
        {
          const $t28667 = (!pressed);
          {
            const $t28669 = (() => {
              {
                const $t28668 = game.special_charges;
                return ($t28668 <= 0);
              }
            })();
            return ($t28667 || $t28669);
          }
        }
      })();
      if ($t28670 === true) {
        return game;
      } else {
        return (() => {
          {
            const $t28671 = game.special;
            switch ($t28671.$) {
              case "None": {
                return game;
                break;
              }
              case "Some": {
                const $f28702 = $t28671._0;
                switch ($f28702.$) {
                  case "StarThrust": {
                    {
                      const $t28672 = Perihelion$Core$nearest_star_dir(game);
                      switch ($t28672.$) {
                        case "None": {
                          return game;
                          break;
                        }
                        case "Some": {
                          const $f28701 = $t28672._0;
                          {
                            const pair = $f28701;
                            {
                              const dx = pair._0;
                              {
                                const dy = pair._1;
                                {
                                  const $t28673 = game.mode;
                                  switch ($t28673.$) {
                                    case "Flying": {
                                      const $f28683 = $t28673._0;
                                      const $f28684 = $t28673._1;
                                      {
                                        const vy = (() => {
                                          return $f28684;
                                        })();
                                        {
                                          const vx = (() => {
                                            return $f28683;
                                          })();
                                          {
                                            const $t28680 = (() => {
                                              {
                                                const $t28676 = (() => {
                                                  {
                                                    const $t28675 = (dx * 60.);
                                                    return (vx + $t28675);
                                                  }
                                                })();
                                                {
                                                  const $t28679 = (() => {
                                                    {
                                                      const $t28678 = (dy * 60.);
                                                      return (vy + $t28678);
                                                    }
                                                  })();
                                                  return { $: "Flying", _0: $t28676, _1: $t28679 };
                                                }
                                              }
                                            })();
                                            {
                                              const $t28682 = (() => {
                                                {
                                                  const $t28681 = game.special_charges;
                                                  return ($t28681 - 1);
                                                }
                                              })();
                                              return ({ ...game, mode: $t28680, special_charges: $t28682 });
                                            }
                                          }
                                        }
                                      }
                                      break;
                                    }
                                    case "Orbiting": {
                                      const $f28689 = $t28673._0;
                                      const $f28690 = $t28673._1;
                                      const $f28691 = $t28673._2;
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
        const $t28707 = { $: "Nil" };
        {
          const $t28708 = { $: "None" };
          return ({ ...game, view_w: view_w, view_h: view_h, fx_bursts: $t28707, capture_flash: $t28708 });
        }
      }
    })();
    {
      const $t28709 = (() => {
        {
          const $t28706_i4969 = { $: "$Clo_$lam28703$3775", _0: $lam28703$apply$3775 };
          return List$any$List_String$Fn_String_Bool(keys, $t28706_i4969);
        }
      })();
      if ($t28709 === true) {
        return Perihelion$Core$reset(g0);
      } else {
        return (() => {
          {
            const tapped = (() => {
              {
                let $t28710;
                switch (taps.$) {
                  case "Nil": {
                    $t28710 = true;
                    break;
                  }
                  default: {
                    $t28710 = false;
                    break;
                  }
                }
                return (!$t28710);
              }
            })();
            {
              const $t28711 = g0.phase;
              switch ($t28711.$) {
                case "Ready": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28712 = { $: "Playing" };
                        return ({ ...g0, phase: $t28712 });
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
                        const $t28714 = (() => {
                          {
                            const $t28713 = g0.milestone_choices;
                            return List$nth_opt$List_UpgradeKind$Int($t28713, 0);
                          }
                        })();
                        switch ($t28714.$) {
                          case "None": {
                            return g0;
                            break;
                          }
                          case "Some": {
                            const $f28719 = $t28714._0;
                            {
                              const choice = $f28719;
                              {
                                const $t28718 = (() => {
                                  {
                                    const $t28715 = Perihelion$Core$apply_upgrade(g0, choice);
                                    {
                                      const $t28716 = { $: "Playing" };
                                      {
                                        const $t28717 = { $: "Nil" };
                                        return ({ ...$t28715, phase: $t28716, milestone_choices: $t28717 });
                                      }
                                    }
                                  }
                                })();
                                return Perihelion$Core$top_up($t28718);
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
        const $t28720 = game.mode;
        switch ($t28720.$) {
          case "Orbiting": {
            const $f28721 = $t28720._0;
            const $f28722 = $t28720._1;
            const $f28723 = $t28720._2;
            {
              const angle = (() => {
                return $f28723;
              })();
              {
                const ring = (() => {
                  return $f28722;
                })();
                {
                  const idx = (() => {
                    return $f28721;
                  })();
                  return Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s);
                }
              }
            }
            break;
          }
          case "Flying": {
            const $f28732 = $t28720._0;
            const $f28733 = $t28720._1;
            {
              const vy = (() => {
                return $f28733;
              })();
              {
                const vx = (() => {
                  return $f28732;
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
          const $t28738 = g0.owned_weapons;
          {
            const go_i4980 = { $: "$Clo_go$4810", _0: go$apply$4810 };
            return go$apply$4810(go_i4980, $t28738, 0);
          }
        }
      })();
      {
        const g1a = (() => {
          {
            const $t28740 = (() => {
              {
                const $t28739 = g0.active_weapon_idx;
                return Perihelion$Core$adjust_weapon($t28739, keys, n);
              }
            })();
            return ({ ...g0, active_weapon_idx: $t28740 });
          }
        })();
        {
          const g1 = (() => {
            {
              const $t28742 = (() => {
                {
                  const $t28741 = g1a.starkiller_target_offset;
                  return Perihelion$Core$adjust_starkiller_target($t28741, keys);
                }
              })();
              return ({ ...g1a, starkiller_target_offset: $t28742 });
            }
          })();
          {
            const g1x = (() => {
              return Perihelion$Core$apply_special(g1, keys);
            })();
            {
              const $t28743 = g1x.phase;
              switch ($t28743.$) {
                case "Playing": {
                  {
                    const g2 = (() => {
                      {
                        const g1_i4977 = Perihelion$Combat$step_spawn(g1x, dt_s);
                        {
                          const g2_i4978 = Perihelion$Combat$step_entities(g1_i4977, dt_s);
                          return Perihelion$Combat$step_ships(g2_i4978, dt_s);
                        }
                      }
                    })();
                    {
                      const g3 = Perihelion$Combat$fire(g2, keys, cursor, dt_s);
                      {
                        const g4 = (() => {
                          {
                            const g0_i4971 = Perihelion$Combat$collide_shots_stars(g3);
                            {
                              const g1_i4972 = Perihelion$Combat$collide_shots_asteroids(g0_i4971);
                              {
                                const g2_i4973 = Perihelion$Combat$collide_shots_ships(g1_i4972);
                                {
                                  const g3_i4974 = Perihelion$Combat$collide_ball_pickups(g2_i4973);
                                  return Perihelion$Combat$collide_ball_hazards(g3_i4974);
                                }
                              }
                            }
                          }
                        })();
                        {
                          const $t28744 = (() => {
                            return g4.phase;
                          })();
                          switch ($t28744.$) {
                            case "Playing": {
                              {
                                const $t28745 = (() => {
                                  {
                                    const $rc_618 = Perihelion$Core$step_camera(g4, dt_s);
                                    return $rc_618;
                                  }
                                })();
                                return Perihelion$Core$top_up($t28745);
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
    const $t28746 = Perihelion$Core$star_at(game, idx);
    switch ($t28746.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28769 = $t28746._0;
        {
          const s = $f28769;
          if (tapped === true) {
            return (() => {
              {
                const vx_i4994 = (() => {
                  {
                    const $t28773_i4993 = (() => {
                      {
                        const $t28771_i4991 = (1. * 340.);
                        {
                          const $t28772_i4992 = Math.sin(angle);
                          return ($t28771_i4991 * $t28772_i4992);
                        }
                      }
                    })();
                    return (0. - $t28773_i4993);
                  }
                })();
                {
                  const vy_i4998 = (() => {
                    {
                      const $t28775_i4996 = (1. * 340.);
                      {
                        const $t28776_i4997 = Math.cos(angle);
                        return ($t28775_i4996 * $t28776_i4997);
                      }
                    }
                  })();
                  {
                    const $t28777_i4999 = { $: "Flying", _0: vx_i4994, _1: vy_i4998 };
                    return ({ ...game, mode: $t28777_i4999 });
                  }
                }
              }
            })();
          } else {
            return (() => {
              {
                const ring2 = (() => {
                  {
                    const $t28747 = Perihelion$Core$ring_count(s);
                    return Perihelion$Core$adjust_ring(ring, keys, $t28747);
                  }
                })();
                {
                  const o = Perihelion$Core$ring_at(s, ring2);
                  {
                    const a2 = (() => {
                      {
                        const $t28753 = (() => {
                          {
                            const $t28752 = (() => {
                              {
                                const $t28750 = (1. * 1.8);
                                {
                                  const $t28751 = o.speed_mult;
                                  return ($t28750 * $t28751);
                                }
                              }
                            })();
                            return ($t28752 * dt_s);
                          }
                        })();
                        return (angle + $t28753);
                      }
                    })();
                    {
                      const r = o.radius;
                      {
                        const $t28754 = { $: "Orbiting", _0: idx, _1: ring2, _2: a2 };
                        {
                          const $t28760 = (() => {
                            {
                              const $t28755 = game.loop_angle;
                              {
                                const $t28759 = (() => {
                                  {
                                    const $t28758 = (() => {
                                      {
                                        const $t28757 = o.speed_mult;
                                        return (1.8 * $t28757);
                                      }
                                    })();
                                    return ($t28758 * dt_s);
                                  }
                                })();
                                return ($t28755 + $t28759);
                              }
                            }
                          })();
                          {
                            const $t28764 = (() => {
                              {
                                const $t28761 = s.x;
                                {
                                  const $t28763 = (() => {
                                    {
                                      const $t28762 = Math.cos(a2);
                                      return ($t28762 * r);
                                    }
                                  })();
                                  return ($t28761 + $t28763);
                                }
                              }
                            })();
                            {
                              const $t28768 = (() => {
                                {
                                  const $t28765 = s.y;
                                  {
                                    const $t28767 = (() => {
                                      {
                                        const $t28766 = Math.sin(a2);
                                        return ($t28766 * r);
                                      }
                                    })();
                                    return ($t28765 + $t28767);
                                  }
                                }
                              })();
                              return ({ ...game, mode: $t28754, loop_angle: $t28760, ball_x: $t28764, ball_y: $t28768 });
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
        const $t28780 = (() => {
          {
            const $t28778 = (vx * vx);
            {
              const $t28779 = (vy * vy);
              return ($t28778 + $t28779);
            }
          }
        })();
        return Math.sqrt($t28780);
      }
    })();
    {
      const $t28781 = (m > 0.);
      if ($t28781 === true) {
        return (() => {
          {
            const out = (() => {
              {
                const $t28784 = (() => {
                  {
                    const $t28782 = (vx / m);
                    return ($t28782 * 340.);
                  }
                })();
                {
                  const $t28787 = (() => {
                    {
                      const $t28785 = (vy / m);
                      return ($t28785 * 340.);
                    }
                  })();
                  return { _0: $t28784, _1: $t28787 };
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
      const $f28806 = stars._0;
      const $f28807 = stars._1;
      {
        const rest = $f28807;
        {
          const s = $f28806;
          {
            const dx = (() => {
              {
                const $t28788 = s.x;
                {
                  const $t28789 = game.ball_x;
                  return ($t28788 - $t28789);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28790 = s.y;
                  {
                    const $t28791 = game.ball_y;
                    return ($t28790 - $t28791);
                  }
                }
              })();
              {
                const d = (() => {
                  {
                    const $t28794 = (() => {
                      {
                        const $t28792 = (dx * dx);
                        {
                          const $t28793 = (dy * dy);
                          return ($t28792 + $t28793);
                        }
                      }
                    })();
                    return Math.sqrt($t28794);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28797 = (() => {
                        {
                          const $t28795 = (vx * dx);
                          {
                            const $t28796 = (vy * dy);
                            return ($t28795 + $t28796);
                          }
                        }
                      })();
                      return ($t28797 > 0.);
                    }
                  })();
                  {
                    const $t28804 = (() => {
                      {
                        const $t28802 = (() => {
                          {
                            const $t28801 = (() => {
                              {
                                const $t28800 = (() => {
                                  {
                                    const $t28799 = s.capture_radius;
                                    return (2.4 * $t28799);
                                  }
                                })();
                                return (d < $t28800);
                              }
                            })();
                            return (approaching && $t28801);
                          }
                        })();
                        {
                          const $t28803 = (d < best_d);
                          return ($t28802 && $t28803);
                        }
                      }
                    })();
                    if ($t28804 === true) {
                      return (() => {
                        {
                          const $t28805 = { $: "Some", _0: s };
                          return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, $t28805, d);
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
    const $t28814 = (() => {
      {
        const $t28812 = game.stars;
        {
          const $t28813 = { $: "None" };
          return Perihelion$Core$nearest_assist_target(game, vx, vy, $t28812, $t28813, 999999.);
        }
      }
    })();
    switch ($t28814.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f28833 = $t28814._0;
        {
          const t = $f28833;
          {
            const dx = (() => {
              {
                const $t28815 = t.x;
                {
                  const $t28816 = game.ball_x;
                  return ($t28815 - $t28816);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28817 = t.y;
                  {
                    const $t28818 = game.ball_y;
                    return ($t28817 - $t28818);
                  }
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t28821 = (() => {
                      {
                        const $t28819 = (dx * dx);
                        {
                          const $t28820 = (dy * dy);
                          return ($t28819 + $t28820);
                        }
                      }
                    })();
                    return Math.sqrt($t28821);
                  }
                })();
                {
                  const $t28822 = (dist > 0.);
                  if ($t28822 === true) {
                    return (() => {
                      {
                        const $t28827 = (() => {
                          {
                            const $t28826 = (() => {
                              {
                                const $t28825 = (() => {
                                  {
                                    const $t28823 = (dx / dist);
                                    return ($t28823 * 1600.);
                                  }
                                })();
                                return ($t28825 * dt_s);
                              }
                            })();
                            return (vx + $t28826);
                          }
                        })();
                        {
                          const $t28832 = (() => {
                            {
                              const $t28831 = (() => {
                                {
                                  const $t28830 = (() => {
                                    {
                                      const $t28828 = (dy / dist);
                                      return ($t28828 * 1600.);
                                    }
                                  })();
                                  return ($t28830 * dt_s);
                                }
                              })();
                              return (vy + $t28831);
                            }
                          })();
                          return Perihelion$Core$renormalize($t28827, $t28832);
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
    const $t28834 = (n === 0);
    if ($t28834 === true) {
      return (() => {
        {
          const go_i5009 = { $: "$Clo_go$4341", _0: go$apply$4341 };
          {
            const $t274_i5010 = { $: "Nil" };
            return go$apply$4341(go_i5009, acc, $t274_i5010);
          }
        }
      })();
    } else {
      return (() => {
        {
          const simmed = ({ ...game, ball_x: x, ball_y: y });
          {
            const $p28843 = Perihelion$Core$assisted_velocity(simmed, vx, vy, 0.05);
            {
              const vx2 = $p28843._0;
              {
                const vy2 = $p28843._1;
                {
                  const x2 = (() => {
                    {
                      const $t28837 = (vx2 * 0.05);
                      return (x + $t28837);
                    }
                  })();
                  {
                    const y2 = (() => {
                      {
                        const $t28839 = (vy2 * 0.05);
                        return (y + $t28839);
                      }
                    })();
                    {
                      const $t28840 = (n - 1);
                      {
                        const $t28841 = { _0: x2, _1: y2 };
                        {
                          const $t28842 = { $: "Cons", _0: $t28841, _1: acc };
                          return Perihelion$Core$predict_trajectory_go(game, x2, y2, vx2, vy2, $t28840, $t28842);
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
    const $t28844 = Perihelion$Core$star_at(game, idx);
    switch ($t28844.$) {
      case "None": {
        return { $: "Nil" };
        break;
      }
      case "Some": {
        const $f28874 = $t28844._0;
        {
          const s = $f28874;
          {
            const o = Perihelion$Core$ring_at(s, ring);
            {
              const start_x = (() => {
                {
                  const $t28845 = s.x;
                  {
                    const $t28848 = (() => {
                      {
                        const $t28846 = Math.cos(angle);
                        {
                          const $t28847 = o.radius;
                          return ($t28846 * $t28847);
                        }
                      }
                    })();
                    return ($t28845 + $t28848);
                  }
                }
              })();
              {
                const start_y = (() => {
                  {
                    const $t28849 = s.y;
                    {
                      const $t28852 = (() => {
                        {
                          const $t28850 = Math.sin(angle);
                          {
                            const $t28851 = o.radius;
                            return ($t28850 * $t28851);
                          }
                        }
                      })();
                      return ($t28849 + $t28852);
                    }
                  }
                })();
                {
                  const $t28854 = (() => {
                    {
                      const $t28853 = (() => {
                        {
                          const vx_i5021 = (() => {
                            {
                              const $t28773_i5020 = (() => {
                                {
                                  const $t28771_i5018 = (1. * 340.);
                                  {
                                    const $t28772_i5019 = Math.sin(angle);
                                    return ($t28771_i5018 * $t28772_i5019);
                                  }
                                }
                              })();
                              return (0. - $t28773_i5020);
                            }
                          })();
                          {
                            const vy_i5025 = (() => {
                              {
                                const $t28775_i5023 = (1. * 340.);
                                {
                                  const $t28776_i5024 = Math.cos(angle);
                                  return ($t28775_i5023 * $t28776_i5024);
                                }
                              }
                            })();
                            {
                              const $t28777_i5026 = { $: "Flying", _0: vx_i5021, _1: vy_i5025 };
                              return ({ ...game, mode: $t28777_i5026 });
                            }
                          }
                        }
                      })();
                      return $t28853.mode;
                    }
                  })();
                  switch ($t28854.$) {
                    case "Flying": {
                      const $f28857 = $t28854._0;
                      const $f28858 = $t28854._1;
                      {
                        const vy0 = $f28858;
                        {
                          const vx0 = $f28857;
                          {
                            const $t28856 = { $: "Nil" };
                            return Perihelion$Core$predict_trajectory_go(game, start_x, start_y, vx0, vy0, 24, $t28856);
                          }
                        }
                      }
                      break;
                    }
                    case "Orbiting": {
                      const $f28863 = $t28854._0;
                      const $f28864 = $t28854._1;
                      const $f28865 = $t28854._2;
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
      const $f28895 = stars._0;
      const $f28896 = stars._1;
      {
        const rest = $f28896;
        {
          const s = $f28895;
          {
            const dx = (() => {
              {
                const $t28875 = s.x;
                {
                  const $t28876 = game.ball_x;
                  return ($t28875 - $t28876);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28877 = s.y;
                  {
                    const $t28878 = game.ball_y;
                    return ($t28877 - $t28878);
                  }
                }
              })();
              {
                const grace = (() => {
                  {
                    const $t28879 = s.capture_radius;
                    return ($t28879 + 6.);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28883 = (() => {
                        {
                          const $t28881 = (vx * dx);
                          {
                            const $t28882 = (vy * dy);
                            return ($t28881 + $t28882);
                          }
                        }
                      })();
                      return ($t28883 > 0.);
                    }
                  })();
                  {
                    const $t28892 = (() => {
                      {
                        const $t28886 = (() => {
                          {
                            const $t28885 = (() => {
                              {
                                const $t28884 = game.current;
                                return (i !== $t28884);
                              }
                            })();
                            return ($t28885 && approaching);
                          }
                        })();
                        {
                          const $t28891 = (() => {
                            {
                              const $t28890 = (() => {
                                {
                                  const $t28889 = (() => {
                                    {
                                      const $t28887 = (dx * dx);
                                      {
                                        const $t28888 = (dy * dy);
                                        return ($t28887 + $t28888);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t28889);
                                }
                              })();
                              return ($t28890 <= grace);
                            }
                          })();
                          return ($t28886 && $t28891);
                        }
                      }
                    })();
                    if ($t28892 === true) {
                      return (() => {
                        {
                          const $t28893 = { _0: i, _1: s };
                          return { $: "Some", _0: $t28893 };
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const $t28894 = (i + 1);
                          return Perihelion$Core$find_capture(game, vx, vy, rest, $t28894);
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
    const $p28917 = Perihelion$Core$assisted_velocity(game, vx, vy, dt_s);
    {
      const vx2 = $p28917._0;
      {
        const vy2 = $p28917._1;
        {
          const g = (() => {
            {
              const $t28903 = (() => {
                {
                  const $t28901 = game.ball_x;
                  {
                    const $t28902 = (vx2 * dt_s);
                    return ($t28901 + $t28902);
                  }
                }
              })();
              {
                const $t28906 = (() => {
                  {
                    const $t28904 = game.ball_y;
                    {
                      const $t28905 = (vy2 * dt_s);
                      return ($t28904 + $t28905);
                    }
                  }
                })();
                {
                  const $t28907 = { $: "Flying", _0: vx2, _1: vy2 };
                  return ({ ...game, ball_x: $t28903, ball_y: $t28906, mode: $t28907 });
                }
              }
            }
          })();
          {
            const $t28909 = (() => {
              {
                const $t28908 = g.stars;
                return Perihelion$Core$find_capture(g, vx2, vy2, $t28908, 0);
              }
            })();
            switch ($t28909.$) {
              case "None": {
                return Perihelion$Core$check_death(g);
                break;
              }
              case "Some": {
                const $f28910 = $t28909._0;
                const $f28911 = $f28910._0;
                const $f28912 = $f28910._1;
                {
                  const t = $f28912;
                  {
                    const idx = $f28911;
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
        const $t28920 = (() => {
          {
            const $t28918 = game.ball_y;
            {
              const $t28919 = captured.y;
              return ($t28918 - $t28919);
            }
          }
        })();
        {
          const $t28923 = (() => {
            {
              const $t28921 = game.ball_x;
              {
                const $t28922 = captured.x;
                return ($t28921 - $t28922);
              }
            }
          })();
          return Math.atan2($t28920, $t28923);
        }
      }
    })();
    {
      const snapped = (() => {
        {
          const $t28925 = (() => {
            {
              const $t28924 = (() => {
                {
                  const $t28574_i5039 = Perihelion$Core$ring_count(captured);
                  return ($t28574_i5039 - 1);
                }
              })();
              return { $: "Orbiting", _0: idx, _1: $t28924, _2: angle };
            }
          })();
          {
            const $t28930 = (() => {
              {
                const $t28926 = captured.x;
                {
                  const $t28929 = (() => {
                    {
                      const $t28927 = Math.cos(angle);
                      {
                        const $t28928 = captured.capture_radius;
                        return ($t28927 * $t28928);
                      }
                    }
                  })();
                  return ($t28926 + $t28929);
                }
              }
            })();
            {
              const $t28935 = (() => {
                {
                  const $t28931 = captured.y;
                  {
                    const $t28934 = (() => {
                      {
                        const $t28932 = Math.sin(angle);
                        {
                          const $t28933 = captured.capture_radius;
                          return ($t28932 * $t28933);
                        }
                      }
                    })();
                    return ($t28931 + $t28934);
                  }
                }
              })();
              return ({ ...game, mode: $t28925, loop_angle: 0., ball_x: $t28930, ball_y: $t28935 });
            }
          }
        }
      })();
      {
        const $t28937 = (() => {
          {
            const $t28936 = game.current;
            return (idx > $t28936);
          }
        })();
        if ($t28937 === true) {
          return (() => {
            {
              const new_mult = (() => {
                {
                  const $t28940 = (() => {
                    {
                      const $t28938 = game.loop_angle;
                      return ($t28938 < 6.28318530718);
                    }
                  })();
                  if ($t28940 === true) {
                    return (() => {
                      {
                        const $t28944 = (() => {
                          {
                            const $t28942 = (() => {
                              {
                                const $t28941 = game.multiplier;
                                return ($t28941 + 1);
                              }
                            })();
                            return ($t28942 > 5);
                          }
                        })();
                        if ($t28944 === true) {
                          return 5;
                        } else {
                          return (() => {
                            {
                              const $t28945 = game.multiplier;
                              return ($t28945 + 1);
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
                    const $t28946 = game.stars_chained;
                    return ($t28946 + 1);
                  }
                })();
                {
                  const captured_game = (() => {
                    {
                      const $t28948 = (() => {
                        {
                          const $t28947 = game.score;
                          return ($t28947 + new_mult);
                        }
                      })();
                      {
                        const $t28950 = (() => {
                          {
                            const $t28949 = game.max_mult;
                            {
                              const $t29020_i5035 = ($t28949 > new_mult);
                              if ($t29020_i5035 === true) {
                                return $t28949;
                              } else {
                                return new_mult;
                              }
                            }
                          }
                        })();
                        {
                          const $t28954 = (() => {
                            {
                              const $t28951 = captured.x;
                              {
                                const $t28952 = captured.y;
                                {
                                  const $t28953 = { _0: $t28951, _1: $t28952 };
                                  return { $: "Some", _0: $t28953 };
                                }
                              }
                            }
                          })();
                          return ({ ...snapped, current: idx, score: $t28948, stars_chained: new_chained, multiplier: new_mult, max_mult: $t28950, capture_flash: $t28954 });
                        }
                      }
                    }
                  })();
                  {
                    const $t28955 = Perihelion$Upgrades$is_milestone(new_chained);
                    if ($t28955 === true) {
                      return (() => {
                        {
                          const $p28961 = (() => {
                            {
                              const $t28956 = captured_game.rng;
                              {
                                const $t28957 = captured_game.owned_weapons;
                                {
                                  const $t28958 = captured_game.special;
                                  return Perihelion$Upgrades$draw_choices($t28956, $t28957, $t28958);
                                }
                              }
                            }
                          })();
                          {
                            const rng2 = $p28961._0;
                            {
                              const choices = $p28961._1;
                              {
                                const $t28960 = (() => {
                                  {
                                    const $t28959 = { $: "Milestone" };
                                    return ({ ...captured_game, phase: $t28959, rng: rng2, milestone_choices: choices });
                                  }
                                })();
                                return Perihelion$Core$top_up($t28960);
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
        const $t28962 = { $: "Nil" };
        {
          const $t28963 = { $: "None" };
          return ({ ...game, fx_bursts: $t28962, capture_flash: $t28963 });
        }
      }
    })();
    switch (choice_idx.$) {
      case "None": {
        return g0;
        break;
      }
      case "Some": {
        const $f28971 = choice_idx._0;
        {
          const i = $f28971;
          {
            const $t28965 = (() => {
              {
                const $t28964 = g0.milestone_choices;
                return List$nth_opt$List_UpgradeKind$Int($t28964, i);
              }
            })();
            switch ($t28965.$) {
              case "None": {
                return g0;
                break;
              }
              case "Some": {
                const $f28970 = $t28965._0;
                {
                  const choice = $f28970;
                  {
                    const $t28969 = (() => {
                      {
                        const $t28966 = Perihelion$Core$apply_upgrade(g0, choice);
                        {
                          const $t28967 = { $: "Playing" };
                          {
                            const $t28968 = { $: "Nil" };
                            return ({ ...$t28966, phase: $t28967, milestone_choices: $t28968 });
                          }
                        }
                      }
                    })();
                    return Perihelion$Core$top_up($t28969);
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
      const $f28984 = u._0;
      {
        const k = $f28984;
        {
          const $t28973 = (() => {
            {
              const $t28972 = game.owned_weapons;
              {
                const $t690_i5051 = { $: "$Clo_$lam689$4794", _0: $lam689$apply$4794, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28972, $t690_i5051);
              }
            }
          })();
          if ($t28973 === true) {
            return game;
          } else {
            return (() => {
              {
                const $t28974 = game.owned_weapons;
                {
                  const $t28975 = { $: "Nil" };
                  {
                    const $t28976 = { $: "Cons", _0: k, _1: $t28975 };
                    {
                      const $t28977 = (() => {
                        {
                          const go_i5047 = { $: "$Clo_go$4813", _0: go$apply$4813 };
                          {
                            const $t282_i5048 = (() => {
                              {
                                const go_i12035 = { $: "$Clo_go$5275", _0: go$apply$5275 };
                                {
                                  const $t274_i12036 = { $: "Nil" };
                                  return go$apply$5275(go_i12035, $t28974, $t274_i12036);
                                }
                              }
                            })();
                            return go$apply$4813(go_i5047, $t282_i5048, $t28976);
                          }
                        }
                      })();
                      return ({ ...game, owned_weapons: $t28977 });
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
        const $t28979 = (() => {
          {
            const $t28978 = game.fire_rate_stacks;
            return ($t28978 + 1);
          }
        })();
        return ({ ...game, fire_rate_stacks: $t28979 });
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
        const $t28981 = (() => {
          {
            const $t28980 = game.shield;
            return ($t28980 + 1);
          }
        })();
        return ({ ...game, shield: $t28981, shield_reinforced: true });
      }
      break;
    }
    case "SpecialItem": {
      const $f28985 = u._0;
      {
        const k = $f28985;
        {
          const $t28982 = (() => {
            return { $: "Some", _0: k };
          })();
          {
            const $t28983 = (() => {
              {
                let $rc_619;
                switch (k.$) {
                  case "StarThrust": {
                    $rc_619 = 3;
                    break;
                  }
                  case "StarJump": {
                    $rc_619 = 1;
                    break;
                  }
                  case "TrajectoryPreview": {
                    $rc_619 = 0;
                    break;
                  }
                  default: {
                    $rc_619 = (() => { throw new Error("non-exhaustive pattern match"); })();
                    break;
                  }
                }
                return $rc_619;
              }
            })();
            return ({ ...game, special: $t28982, special_charges: $t28983 });
          }
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
        const $t28987 = (() => {
          {
            const $t28986 = game.view_w;
            return ($t28986 / 2.);
          }
        })();
        {
          const $t28988 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28989 = { $: "Nil" };
            {
              const $t28990 = { $: "Cons", _0: $t28988, _1: $t28989 };
              return ({ x: $t28987, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28990 });
            }
          }
        }
      }
    })();
    {
      const top = (() => {
        {
          const $t28991 = game.stars;
          return Perihelion$Core$top_star($t28991, fallback);
        }
      })();
      {
        const $t28998 = (() => {
          {
            const $t28992 = top.y;
            {
              const $t28997 = (() => {
                {
                  const $t28993 = game.camera_y;
                  {
                    const $t28996 = (() => {
                      {
                        const $t28994 = game.view_h;
                        return ($t28994 * 1.5);
                      }
                    })();
                    return ($t28993 - $t28996);
                  }
                }
              })();
              return ($t28992 > $t28997);
            }
          }
        })();
        if ($t28998 === true) {
          return (() => {
            {
              const $p29009 = (() => {
                {
                  const $t28999 = game.rng;
                  {
                    const $t29000 = game.view_w;
                    return Perihelion$Level$next_star($t28999, top, $t29000);
                  }
                }
              })();
              {
                const fresh = $p29009._0;
                {
                  const rng2 = $p29009._1;
                  {
                    const g2 = (() => {
                      {
                        const $t29001 = game.stars;
                        {
                          const $t29002 = { $: "Nil" };
                          {
                            const $t29003 = { $: "Cons", _0: fresh, _1: $t29002 };
                            {
                              const $t29004 = (() => {
                                {
                                  const go_i5058 = { $: "$Clo_go$4801", _0: go$apply$4801 };
                                  {
                                    const $t282_i5059 = (() => {
                                      {
                                        const go_i12039 = { $: "$Clo_go$5273", _0: go$apply$5273 };
                                        {
                                          const $t274_i12040 = { $: "Nil" };
                                          return go$apply$5273(go_i12039, $t29001, $t274_i12040);
                                        }
                                      }
                                    })();
                                    return go$apply$4801(go_i5058, $t282_i5059, $t29003);
                                  }
                                }
                              })();
                              return ({ ...game, stars: $t29004, rng: rng2 });
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t29008 = (() => {
                        {
                          const $t29007 = (() => {
                            {
                              const $t29006 = (() => {
                                {
                                  const $t29005 = g2.stars;
                                  {
                                    const go_i5055 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                                    return go$apply$4761(go_i5055, $t29005, 0);
                                  }
                                }
                              })();
                              return ($t29006 - 1);
                            }
                          })();
                          return Perihelion$Combat$maybe_spawn_ship(g2, $t29007);
                        }
                      })();
                      return Perihelion$Core$top_up($t29008);
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
      const $f29010 = stars._0;
      const $f29011 = stars._1;
      {
        const $jp_clo29017 = (() => {
          return { $: "$Clo_$jp29016$3787", _0: $jp29016$apply$3787, _1: $f29011, _2: fallback };
        })();
        switch ($f29011.$) {
          case "Nil": {
            {
              const s = $f29010;
              return s;
            }
            break;
          }
          default: {
            return $jp29016$apply$3787($jp_clo29017);
          }
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
        const $t29021 = game.score;
        {
          const $t29022 = game.stars_chained;
          {
            const $t29023 = game.max_mult;
            return ({ score: $t29021, stars: $t29022, max_mult: $t29023 });
          }
        }
      }
    })();
    {
      const $t29024 = { $: "Over" };
      {
        const $t29027 = (() => {
          {
            const $t29025 = game.best;
            {
              const $t29026 = game.score;
              {
                const $t29020_i5067 = ($t29025 > $t29026);
                if ($t29020_i5067 === true) {
                  return $t29025;
                } else {
                  return $t29026;
                }
              }
            }
          }
        })();
        {
          const $t29028 = game.runs;
          {
            const $t29029 = (() => {
              return { $: "Cons", _0: rec, _1: $t29028 };
            })();
            {
              const $t29030 = (() => {
                {
                  const go_i5063 = { $: "$Clo_go$4815", _0: go$apply$4815 };
                  {
                    const $t529_i5064 = { $: "Nil" };
                    return go$apply$4815(go_i5063, $t29029, 10, $t529_i5064);
                  }
                }
              })();
              return ({ ...game, phase: $t29024, best: $t29027, runs: $t29030 });
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
        const $t29031 = game.ball_y;
        {
          const $t29036 = (() => {
            {
              const $t29034 = (() => {
                {
                  const $t29032 = game.camera_y;
                  {
                    const $t29033 = game.view_h;
                    return ($t29032 + $t29033);
                  }
                }
              })();
              return ($t29034 + 40.);
            }
          })();
          return ($t29031 > $t29036);
        }
      }
    })();
    {
      const off_side = (() => {
        {
          const $t29040 = (() => {
            {
              const $t29037 = game.ball_x;
              {
                const $t29039 = (0. - 40.);
                return ($t29037 < $t29039);
              }
            }
          })();
          {
            const $t29045 = (() => {
              {
                const $t29041 = game.ball_x;
                {
                  const $t29044 = (() => {
                    {
                      const $t29042 = game.view_w;
                      return ($t29042 + 40.);
                    }
                  })();
                  return ($t29041 > $t29044);
                }
              }
            })();
            return ($t29040 || $t29045);
          }
        }
      })();
      {
        const fallback = (() => {
          {
            const $t29047 = (() => {
              {
                const $t29046 = game.view_w;
                return ($t29046 / 2.);
              }
            })();
            {
              const $t29048 = ({ radius: 54., speed_mult: 1. });
              {
                const $t29049 = { $: "Nil" };
                {
                  const $t29050 = { $: "Cons", _0: $t29048, _1: $t29049 };
                  return ({ x: $t29047, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29050 });
                }
              }
            }
          }
        })();
        {
          const topmost = (() => {
            {
              const $t29051 = game.stars;
              return Perihelion$Core$top_star($t29051, fallback);
            }
          })();
          {
            const overshot = (() => {
              {
                const $t29052 = game.ball_y;
                {
                  const $t29055 = (() => {
                    {
                      const $t29053 = topmost.y;
                      return ($t29053 - 150.);
                    }
                  })();
                  return ($t29052 < $t29055);
                }
              }
            })();
            {
              const fallen = (() => {
                {
                  const $t29056 = Perihelion$Core$star_at(game, 0);
                  switch ($t29056.$) {
                    case "None": {
                      return false;
                      break;
                    }
                    case "Some": {
                      const $f29061 = $t29056._0;
                      {
                        const c = $f29061;
                        {
                          const $t29057 = game.ball_y;
                          {
                            const $t29060 = (() => {
                              {
                                const $t29058 = c.y;
                                return ($t29058 + 200.);
                              }
                            })();
                            return ($t29057 > $t29060);
                          }
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
                const $t29064 = (() => {
                  {
                    const $t29063 = (() => {
                      {
                        const $t29062 = (below || off_side);
                        return ($t29062 || overshot);
                      }
                    })();
                    return ($t29063 || fallen);
                  }
                })();
                if ($t29064 === true) {
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
        const $t29065 = game.mode;
        switch ($t29065.$) {
          case "Flying": {
            const $f29072 = $t29065._0;
            const $f29073 = $t29065._1;
            (() => {
              return $f29072;
            })();
            return game.ball_x;
            break;
          }
          case "Orbiting": {
            const $f29078 = $t29065._0;
            const $f29079 = $t29065._1;
            const $f29080 = $t29065._2;
            {
              const $t29067 = (() => {
                {
                  const $t29066 = game.current;
                  return Perihelion$Core$star_at(game, $t29066);
                }
              })();
              switch ($t29067.$) {
                case "None": {
                  {
                    const $t29068 = game.camera_x;
                    {
                      const $t29070 = (() => {
                        {
                          const $t29069 = game.view_w;
                          return ($t29069 / 2.);
                        }
                      })();
                      return ($t29068 + $t29070);
                    }
                  }
                  break;
                }
                case "Some": {
                  const $f29071 = $t29067._0;
                  {
                    const s = $f29071;
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
          const $t29089 = game.mode;
          switch ($t29089.$) {
            case "Flying": {
              const $f29101 = $t29089._0;
              const $f29102 = $t29089._1;
              {
                const $t29090 = game.ball_y;
                {
                  const $t29093 = (() => {
                    {
                      const $t29092 = game.view_h;
                      return (0.6 * $t29092);
                    }
                  })();
                  return ($t29090 - $t29093);
                }
              }
              break;
            }
            case "Orbiting": {
              const $f29107 = $t29089._0;
              const $f29108 = $t29089._1;
              const $f29109 = $t29089._2;
              {
                const $t29095 = (() => {
                  {
                    const $t29094 = game.current;
                    return Perihelion$Core$star_at(game, $t29094);
                  }
                })();
                switch ($t29095.$) {
                  case "None": {
                    return game.camera_y;
                    break;
                  }
                  case "Some": {
                    const $f29100 = $t29095._0;
                    {
                      const s = $f29100;
                      {
                        const $t29096 = s.y;
                        {
                          const $t29099 = (() => {
                            {
                              const $t29098 = game.view_h;
                              return (0.6 * $t29098);
                            }
                          })();
                          return ($t29096 - $t29099);
                        }
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
            const $t29118 = game.view_w;
            return ($t29118 * 0.25);
          }
        })();
        {
          const right_edge = (() => {
            {
              const $t29120 = game.view_w;
              {
                const $t29122 = (1. - 0.25);
                return ($t29120 * $t29122);
              }
            }
          })();
          {
            const screen_x = (() => {
              {
                const $t29123 = game.camera_x;
                return (focus_x - $t29123);
              }
            })();
            {
              const target_x = (() => {
                {
                  const $t29124 = (screen_x < left_edge);
                  if ($t29124 === true) {
                    return (focus_x - left_edge);
                  } else {
                    return (() => {
                      {
                        const $t29125 = (screen_x > right_edge);
                        if ($t29125 === true) {
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
                const $t29132 = (() => {
                  {
                    const $t29126 = game.camera_y;
                    {
                      const $t29131 = (() => {
                        {
                          const $t29130 = (() => {
                            {
                              const $t29128 = (() => {
                                {
                                  const $t29127 = game.camera_y;
                                  return (target_y - $t29127);
                                }
                              })();
                              return ($t29128 * 3.);
                            }
                          })();
                          return ($t29130 * dt_s);
                        }
                      })();
                      return ($t29126 + $t29131);
                    }
                  }
                })();
                {
                  const $t29139 = (() => {
                    {
                      const $t29133 = game.camera_x;
                      {
                        const $t29138 = (() => {
                          {
                            const $t29137 = (() => {
                              {
                                const $t29135 = (() => {
                                  {
                                    const $t29134 = game.camera_x;
                                    return (target_x - $t29134);
                                  }
                                })();
                                return ($t29135 * 3.);
                              }
                            })();
                            return ($t29137 * dt_s);
                          }
                        })();
                        return ($t29133 + $t29138);
                      }
                    }
                  })();
                  return ({ ...game, camera_y: $t29132, camera_x: $t29139 });
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
    const $p29193 = (() => {
      {
        const $t29140 = Random$seed(seed);
        return Perihelion$Level$initial_stars($t29140, view_w);
      }
    })();
    {
      const stars = $p29193._0;
      {
        const rng2 = $p29193._1;
        {
          const start_angle = (3.14159265359 / 2.);
          switch (stars.$) {
            case "Nil": {
              {
                const $t29142 = { $: "Ready" };
                {
                  const $t29143 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                  {
                    const $t29144 = { $: "Nil" };
                    {
                      const $t29145 = { $: "Nil" };
                      {
                        const $t29146 = { $: "Nil" };
                        {
                          const $t29147 = { $: "Nil" };
                          {
                            const $t29148 = { $: "Nil" };
                            {
                              const $t29149 = { $: "Nil" };
                              {
                                const $t29150 = { $: "Base" };
                                {
                                  const $t29151 = { $: "Nil" };
                                  {
                                    const $t29152 = { $: "Cons", _0: $t29150, _1: $t29151 };
                                    {
                                      const $t29153 = { $: "None" };
                                      {
                                        const $t29154 = { $: "Nil" };
                                        {
                                          const $t29156 = { $: "Nil" };
                                          {
                                            const $t29157 = { $: "None" };
                                            return ({ seed: seed, phase: $t29142, ball_x: 0., ball_y: 0., mode: $t29143, stars: $t29144, current: 0, score: 0, best: best, camera_y: 0., camera_x: 0., rng: rng2, asteroids: $t29145, ships: $t29146, player_shots: $t29147, enemy_shots: $t29148, pickups: $t29149, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t29152, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t29153, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t29154, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t29156, capture_flash: $t29157 });
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
              const $f29187 = stars._0;
              const $f29188 = stars._1;
              {
                const s0 = (() => {
                  return $f29187;
                })();
                {
                  const $t29158 = { $: "Ready" };
                  {
                    const $t29163 = (() => {
                      {
                        const $t29159 = s0.x;
                        {
                          const $t29162 = (() => {
                            {
                              const $t29160 = Math.cos(start_angle);
                              {
                                const $t29161 = s0.capture_radius;
                                return ($t29160 * $t29161);
                              }
                            }
                          })();
                          return ($t29159 + $t29162);
                        }
                      }
                    })();
                    {
                      const $t29168 = (() => {
                        {
                          const $t29164 = s0.y;
                          {
                            const $t29167 = (() => {
                              {
                                const $t29165 = Math.sin(start_angle);
                                {
                                  const $t29166 = s0.capture_radius;
                                  return ($t29165 * $t29166);
                                }
                              }
                            })();
                            return ($t29164 + $t29167);
                          }
                        }
                      })();
                      {
                        const $t29169 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                        {
                          const $t29173 = (() => {
                            {
                              const $t29170 = s0.y;
                              {
                                const $t29172 = (0.6 * view_h);
                                return ($t29170 - $t29172);
                              }
                            }
                          })();
                          {
                            const $t29174 = { $: "Nil" };
                            {
                              const $t29175 = { $: "Nil" };
                              {
                                const $t29176 = { $: "Nil" };
                                {
                                  const $t29177 = { $: "Nil" };
                                  {
                                    const $t29178 = { $: "Nil" };
                                    {
                                      const $t29179 = { $: "Base" };
                                      {
                                        const $t29180 = { $: "Nil" };
                                        {
                                          const $t29181 = { $: "Cons", _0: $t29179, _1: $t29180 };
                                          {
                                            const $t29182 = { $: "None" };
                                            {
                                              const $t29183 = { $: "Nil" };
                                              {
                                                const $t29185 = { $: "Nil" };
                                                {
                                                  const $t29186 = { $: "None" };
                                                  return ({ seed: seed, phase: $t29158, ball_x: $t29163, ball_y: $t29168, mode: $t29169, stars: stars, current: 0, score: 0, best: best, camera_y: $t29173, camera_x: 0., rng: rng2, asteroids: $t29174, ships: $t29175, player_shots: $t29176, enemy_shots: $t29177, pickups: $t29178, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t29181, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t29182, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t29183, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t29185, capture_flash: $t29186 });
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
        const $t29199 = (() => {
          {
            const $p29198_i5094 = (() => {
              {
                const $t29197_i5093 = game.rng;
                {
                  const $p15883_i12042 = Random$next_raw($t29197_i5093);
                  {
                    const hi_i12043 = $p15883_i12042._0;
                    {
                      const rng2_i12044 = $p15883_i12042._1;
                      {
                        const $p15882_i12045 = Random$next_raw(rng2_i12044);
                        {
                          const lo_i12046 = $p15882_i12045._0;
                          {
                            const rng3_i12047 = $p15882_i12045._1;
                            {
                              const $t15881_i12051 = (() => {
                                {
                                  const $t15880_i12050 = (() => {
                                    {
                                      const $t15878_i12048 = march_int_and(hi_i12043, 1048575);
                                      return ($t15878_i12048 * 4294967296);
                                    }
                                  })();
                                  return ($t15880_i12050 + lo_i12046);
                                }
                              })();
                              return { _0: $t15881_i12051, _1: rng3_i12047 };
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
              const s_i5095 = $p29198_i5094._0;
              return s_i5095;
            }
          }
        })();
        {
          const $t29200 = game.best;
          {
            const $t29201 = game.runs;
            {
              const $t29202 = game.view_w;
              {
                const $t29203 = game.view_h;
                return Perihelion$Core$fresh_run($t29199, $t29200, $t29201, $t29202, $t29203);
              }
            }
          }
        }
      }
    })();
    {
      const $t29204 = { $: "Playing" };
      return ({ ...g, phase: $t29204 });
    }
  }
}
const Perihelion$Core$restart$clo = { _0: ($_, game) => Perihelion$Core$restart(game) };

function Perihelion$Core$reset(game) {
  {
    const $t29205 = (() => {
      {
        const $p29198_i5098 = (() => {
          {
            const $t29197_i5097 = game.rng;
            {
              const $p15883_i12053 = Random$next_raw($t29197_i5097);
              {
                const hi_i12054 = $p15883_i12053._0;
                {
                  const rng2_i12055 = $p15883_i12053._1;
                  {
                    const $p15882_i12056 = Random$next_raw(rng2_i12055);
                    {
                      const lo_i12057 = $p15882_i12056._0;
                      {
                        const rng3_i12058 = $p15882_i12056._1;
                        {
                          const $t15881_i12062 = (() => {
                            {
                              const $t15880_i12061 = (() => {
                                {
                                  const $t15878_i12059 = march_int_and(hi_i12054, 1048575);
                                  return ($t15878_i12059 * 4294967296);
                                }
                              })();
                              return ($t15880_i12061 + lo_i12057);
                            }
                          })();
                          return { _0: $t15881_i12062, _1: rng3_i12058 };
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
          const s_i5099 = $p29198_i5098._0;
          return s_i5099;
        }
      }
    })();
    {
      const $t29206 = game.best;
      {
        const $t29207 = game.runs;
        {
          const $t29208 = game.view_w;
          {
            const $t29209 = game.view_h;
            return Perihelion$Core$fresh_run($t29205, $t29206, $t29207, $t29208, $t29209);
          }
        }
      }
    }
  }
}
const Perihelion$Core$reset$clo = { _0: ($_, game) => Perihelion$Core$reset(game) };

function Perihelion$Core$encode_run(r) {
  {
    const $t29214 = (() => {
      {
        const $t29211 = (() => {
          {
            const $t29210 = r.score;
            return String($t29210);
          }
        })();
        {
          const $t29213 = (() => {
            {
              const $t29212 = r.stars;
              return String($t29212);
            }
          })();
          {
            const $rc_621 = march_string_concat3($t29211, ":", $t29213);
            return $rc_621;
          }
        }
      }
    })();
    {
      const $t29216 = (() => {
        {
          const $t29215 = r.max_mult;
          return String($t29215);
        }
      })();
      {
        const $rc_620 = march_string_concat3($t29214, ":", $t29216);
        return $rc_620;
      }
    }
  }
}
const Perihelion$Core$encode_run$clo = { _0: ($_, r) => Perihelion$Core$encode_run(r) };

function Perihelion$Core$encode_save(best, runs) {
  {
    const $t29217 = String(best);
    {
      const $t29221 = (() => {
        {
          const $t29219 = { $: "$Clo_$lam29218$3799", _0: $lam29218$apply$3799 };
          {
            const $t29220 = (() => {
              {
                const f_i5103 = $t29219;
                {
                  const go_i5104 = { $: "$Clo_go$4817", _0: go$apply$4817, _1: f_i5103 };
                  {
                    const $t291_i5105 = { $: "Nil" };
                    return go$apply$4817(go_i5104, runs, $t291_i5105);
                  }
                }
              }
            })();
            return march_string_join($t29220, ";");
          }
        }
      })();
      {
        const $rc_622 = march_string_concat3($t29217, "|", $t29221);
        return $rc_622;
      }
    }
  }
}
const Perihelion$Core$encode_save$clo = { _0: ($_, best, runs) => Perihelion$Core$encode_save(best, runs) };

function Perihelion$Core$decode_run(s) {
  {
    const $t29222 = march_string_split(s, ":");
    switch ($t29222.$) {
      case "Cons": {
        const $f29230 = $t29222._0;
        const $f29231 = $t29222._1;
        {
          const $jp_clo29233 = { $: "$Clo_$jp29232$3800", _0: $jp29232$apply$3800 };
          {
            const $jp_clo29237 = { $: "$Clo_$jp29236$3801", _0: $jp29236$apply$3801$clo, _1: $jp_clo29233 };
            switch ($f29231.$) {
              case "Cons": {
                const $f29238 = $f29231._0;
                const $f29239 = $f29231._1;
                {
                  const $jp_clo29241 = { $: "$Clo_$jp29240$3803", _0: $jp29240$apply$3803, _1: $jp_clo29237 };
                  {
                    const $jp_clo29245 = { $: "$Clo_$jp29244$3804", _0: $jp29244$apply$3804, _1: $jp_clo29241 };
                    switch ($f29239.$) {
                      case "Cons": {
                        const $f29246 = $f29239._0;
                        const $f29247 = $f29239._1;
                        {
                          const $jp_clo29249 = { $: "$Clo_$jp29248$3806", _0: $jp29248$apply$3806, _1: $jp_clo29245 };
                          {
                            const $jp_clo29253 = { $: "$Clo_$jp29252$3807", _0: $jp29252$apply$3807, _1: $jp_clo29249 };
                            switch ($f29247.$) {
                              case "Nil": {
                                {
                                  const c = $f29246;
                                  {
                                    const b = $f29238;
                                    {
                                      const a = $f29230;
                                      {
                                        const $t29223 = (() => {
                                          {
                                            const $rc_625 = march_string_to_int(a);
                                            return $rc_625;
                                          }
                                        })();
                                        switch ($t29223.$) {
                                          case "None": {
                                            return { $: "None" };
                                            break;
                                          }
                                          case "Some": {
                                            const $f29229 = $t29223._0;
                                            {
                                              const score = $f29229;
                                              {
                                                const $t29224 = (() => {
                                                  {
                                                    const $rc_624 = march_string_to_int(b);
                                                    return $rc_624;
                                                  }
                                                })();
                                                switch ($t29224.$) {
                                                  case "None": {
                                                    return { $: "None" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f29228 = $t29224._0;
                                                    {
                                                      const stars = $f29228;
                                                      {
                                                        const $t29225 = (() => {
                                                          {
                                                            const $rc_623 = march_string_to_int(c);
                                                            return $rc_623;
                                                          }
                                                        })();
                                                        switch ($t29225.$) {
                                                          case "None": {
                                                            return { $: "None" };
                                                            break;
                                                          }
                                                          case "Some": {
                                                            const $f29227 = $t29225._0;
                                                            {
                                                              const mm = $f29227;
                                                              {
                                                                const $t29226 = ({ score: score, stars: stars, max_mult: mm });
                                                                return { $: "Some", _0: $t29226 };
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
                                return $jp29252$apply$3807($jp_clo29253);
                              }
                            }
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp29244$apply$3804($jp_clo29245);
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return $jp29236$apply$3801($jp_clo29237);
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
        const $t29256 = (() => {
          {
            const go_i5113 = { $: "$Clo_go$4819", _0: go$apply$4819 };
            {
              const $t274_i5114 = { $: "Nil" };
              return go$apply$4819(go_i5113, acc, $t274_i5114);
            }
          }
        })();
        return { $: "Some", _0: $t29256 };
      }
      break;
    }
    case "Cons": {
      const $f29260 = parts._0;
      const $f29261 = parts._1;
      {
        const rest = $f29261;
        {
          const p = $f29260;
          {
            const $t29257 = (() => {
              {
                const $rc_626 = Perihelion$Core$decode_run(p);
                return $rc_626;
              }
            })();
            switch ($t29257.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f29259 = $t29257._0;
                {
                  const r = $f29259;
                  {
                    const $t29258 = { $: "Cons", _0: r, _1: acc };
                    return Perihelion$Core$decode_runs(rest, $t29258);
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
        const $t29266 = { $: "Nil" };
        return { _0: 0, _1: $t29266 };
      }
    })();
    {
      const $t29267 = march_string_split(s, "|");
      switch ($t29267.$) {
        case "Cons": {
          const $f29277 = $t29267._0;
          const $f29278 = $t29267._1;
          switch ($f29278.$) {
            case "Cons": {
              const $f29279 = $f29278._0;
              const $f29280 = $f29278._1;
              switch ($f29280.$) {
                case "Nil": {
                  {
                    const runs_s = $f29279;
                    {
                      const best_s = $f29277;
                      {
                        const $t29268 = (() => {
                          {
                            const $rc_628 = march_string_to_int(best_s);
                            return $rc_628;
                          }
                        })();
                        switch ($t29268.$) {
                          case "None": {
                            return zero;
                            break;
                          }
                          case "Some": {
                            const $f29276 = $t29268._0;
                            {
                              const best = $f29276;
                              if (runs_s === "") {
                                return (() => {
                                  {
                                    const $t29269 = { $: "Nil" };
                                    return { _0: best, _1: $t29269 };
                                  }
                                })();
                              } else {
                                return (() => {
                                  {
                                    const $t29272 = (() => {
                                      {
                                        const $t29270 = (() => {
                                          {
                                            const $rc_627 = march_string_split(runs_s, ";");
                                            return $rc_627;
                                          }
                                        })();
                                        {
                                          const $t29271 = { $: "Nil" };
                                          return Perihelion$Core$decode_runs($t29270, $t29271);
                                        }
                                      }
                                    })();
                                    switch ($t29272.$) {
                                      case "None": {
                                        return zero;
                                        break;
                                      }
                                      case "Some": {
                                        const $f29273 = $t29272._0;
                                        {
                                          const rs = $f29273;
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
        const $t29286 = ({ radius: outer_r, speed_mult: outer_sp });
        {
          const $t29287 = { $: "Nil" };
          return { $: "Cons", _0: $t29286, _1: $t29287 };
        }
      }
    })();
  } else if (n === 2) {
    return (() => {
      {
        const $t29290 = (() => {
          {
            const $t29288 = (outer_r * 0.6);
            {
              const $t29289 = (outer_sp * 1.5);
              return ({ radius: $t29288, speed_mult: $t29289 });
            }
          }
        })();
        {
          const $t29291 = ({ radius: outer_r, speed_mult: outer_sp });
          {
            const $t29292 = { $: "Nil" };
            {
              const $t29293 = { $: "Cons", _0: $t29291, _1: $t29292 };
              return { $: "Cons", _0: $t29290, _1: $t29293 };
            }
          }
        }
      }
    })();
  } else {
    return (() => {
      {
        const $t29296 = (() => {
          {
            const $t29294 = (outer_r * 0.5);
            {
              const $t29295 = (outer_sp * 1.8);
              return ({ radius: $t29294, speed_mult: $t29295 });
            }
          }
        })();
        {
          const $t29299 = (() => {
            {
              const $t29297 = (outer_r * 0.75);
              {
                const $t29298 = (outer_sp * 1.35);
                return ({ radius: $t29297, speed_mult: $t29298 });
              }
            }
          })();
          {
            const $t29300 = ({ radius: outer_r, speed_mult: outer_sp });
            {
              const $t29301 = { $: "Nil" };
              {
                const $t29302 = { $: "Cons", _0: $t29300, _1: $t29301 };
                {
                  const $t29303 = { $: "Cons", _0: $t29299, _1: $t29302 };
                  return { $: "Cons", _0: $t29296, _1: $t29303 };
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
    const $p29333 = (() => {
      {
        const $p29281_i5192 = (() => {
          {
            const $p15886_i12181 = (() => {
              {
                const $p15883_i1921_i12171 = Random$next_raw(rng);
                {
                  const hi_i1922_i12172 = $p15883_i1921_i12171._0;
                  {
                    const rng2_i1923_i12173 = $p15883_i1921_i12171._1;
                    {
                      const $p15882_i1924_i12174 = Random$next_raw(rng2_i1923_i12173);
                      {
                        const lo_i1925_i12175 = $p15882_i1924_i12174._0;
                        {
                          const rng3_i1926_i12176 = $p15882_i1924_i12174._1;
                          {
                            const $t15881_i1930_i12180 = (() => {
                              {
                                const $t15880_i1929_i12179 = (() => {
                                  {
                                    const $t15878_i1927_i12177 = march_int_and(hi_i1922_i12172, 1048575);
                                    return ($t15878_i1927_i12177 * 4294967296);
                                  }
                                })();
                                return ($t15880_i1929_i12179 + lo_i1925_i12175);
                              }
                            })();
                            return { _0: $t15881_i1930_i12180, _1: rng3_i1926_i12176 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i12182 = $p15886_i12181._0;
              {
                const rng2_i12183 = $p15886_i12181._1;
                {
                  const $t15885_i12185 = (() => {
                    {
                      const $t15884_i12184 = bits_i12182;
                      return ($t15884_i12184 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15885_i12185, _1: rng2_i12183 };
                }
              }
            }
          }
        })();
        {
          const t_i5193 = $p29281_i5192._0;
          {
            const rng2_i5194 = $p29281_i5192._1;
            {
              const out_i5195 = { _0: rng2_i5194, _1: t_i5193 };
              return out_i5195;
            }
          }
        }
      }
    })();
    {
      const r1 = $p29333._0;
      {
        const ty = $p29333._1;
        {
          const $p29332 = (() => {
            {
              const $p29281_i5187 = (() => {
                {
                  const $p15886_i12165 = (() => {
                    {
                      const $p15883_i1921_i12155 = Random$next_raw(r1);
                      {
                        const hi_i1922_i12156 = $p15883_i1921_i12155._0;
                        {
                          const rng2_i1923_i12157 = $p15883_i1921_i12155._1;
                          {
                            const $p15882_i1924_i12158 = Random$next_raw(rng2_i1923_i12157);
                            {
                              const lo_i1925_i12159 = $p15882_i1924_i12158._0;
                              {
                                const rng3_i1926_i12160 = $p15882_i1924_i12158._1;
                                {
                                  const $t15881_i1930_i12164 = (() => {
                                    {
                                      const $t15880_i1929_i12163 = (() => {
                                        {
                                          const $t15878_i1927_i12161 = march_int_and(hi_i1922_i12156, 1048575);
                                          return ($t15878_i1927_i12161 * 4294967296);
                                        }
                                      })();
                                      return ($t15880_i1929_i12163 + lo_i1925_i12159);
                                    }
                                  })();
                                  return { _0: $t15881_i1930_i12164, _1: rng3_i1926_i12160 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const bits_i12166 = $p15886_i12165._0;
                    {
                      const rng2_i12167 = $p15886_i12165._1;
                      {
                        const $t15885_i12169 = (() => {
                          {
                            const $t15884_i12168 = bits_i12166;
                            return ($t15884_i12168 / 4.50359962737e+15);
                          }
                        })();
                        return { _0: $t15885_i12169, _1: rng2_i12167 };
                      }
                    }
                  }
                }
              })();
              {
                const t_i5188 = $p29281_i5187._0;
                {
                  const rng2_i5189 = $p29281_i5187._1;
                  {
                    const out_i5190 = { _0: rng2_i5189, _1: t_i5188 };
                    return out_i5190;
                  }
                }
              }
            }
          })();
          {
            const r2 = $p29332._0;
            {
              const tx = $p29332._1;
              {
                const $p29331 = (() => {
                  {
                    const $p29281_i5182 = (() => {
                      {
                        const $p15886_i12149 = (() => {
                          {
                            const $p15883_i1921_i12139 = Random$next_raw(r2);
                            {
                              const hi_i1922_i12140 = $p15883_i1921_i12139._0;
                              {
                                const rng2_i1923_i12141 = $p15883_i1921_i12139._1;
                                {
                                  const $p15882_i1924_i12142 = Random$next_raw(rng2_i1923_i12141);
                                  {
                                    const lo_i1925_i12143 = $p15882_i1924_i12142._0;
                                    {
                                      const rng3_i1926_i12144 = $p15882_i1924_i12142._1;
                                      {
                                        const $t15881_i1930_i12148 = (() => {
                                          {
                                            const $t15880_i1929_i12147 = (() => {
                                              {
                                                const $t15878_i1927_i12145 = march_int_and(hi_i1922_i12140, 1048575);
                                                return ($t15878_i1927_i12145 * 4294967296);
                                              }
                                            })();
                                            return ($t15880_i1929_i12147 + lo_i1925_i12143);
                                          }
                                        })();
                                        return { _0: $t15881_i1930_i12148, _1: rng3_i1926_i12144 };
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        })();
                        {
                          const bits_i12150 = $p15886_i12149._0;
                          {
                            const rng2_i12151 = $p15886_i12149._1;
                            {
                              const $t15885_i12153 = (() => {
                                {
                                  const $t15884_i12152 = bits_i12150;
                                  return ($t15884_i12152 / 4.50359962737e+15);
                                }
                              })();
                              return { _0: $t15885_i12153, _1: rng2_i12151 };
                            }
                          }
                        }
                      }
                    })();
                    {
                      const t_i5183 = $p29281_i5182._0;
                      {
                        const rng2_i5184 = $p29281_i5182._1;
                        {
                          const out_i5185 = { _0: rng2_i5184, _1: t_i5183 };
                          return out_i5185;
                        }
                      }
                    }
                  }
                })();
                {
                  const r3 = $p29331._0;
                  {
                    const tr = $p29331._1;
                    {
                      const $p29330 = (() => {
                        {
                          const $p29281_i5177 = (() => {
                            {
                              const $p15886_i12133 = (() => {
                                {
                                  const $p15883_i1921_i12123 = Random$next_raw(r3);
                                  {
                                    const hi_i1922_i12124 = $p15883_i1921_i12123._0;
                                    {
                                      const rng2_i1923_i12125 = $p15883_i1921_i12123._1;
                                      {
                                        const $p15882_i1924_i12126 = Random$next_raw(rng2_i1923_i12125);
                                        {
                                          const lo_i1925_i12127 = $p15882_i1924_i12126._0;
                                          {
                                            const rng3_i1926_i12128 = $p15882_i1924_i12126._1;
                                            {
                                              const $t15881_i1930_i12132 = (() => {
                                                {
                                                  const $t15880_i1929_i12131 = (() => {
                                                    {
                                                      const $t15878_i1927_i12129 = march_int_and(hi_i1922_i12124, 1048575);
                                                      return ($t15878_i1927_i12129 * 4294967296);
                                                    }
                                                  })();
                                                  return ($t15880_i1929_i12131 + lo_i1925_i12127);
                                                }
                                              })();
                                              return { _0: $t15881_i1930_i12132, _1: rng3_i1926_i12128 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const bits_i12134 = $p15886_i12133._0;
                                {
                                  const rng2_i12135 = $p15886_i12133._1;
                                  {
                                    const $t15885_i12137 = (() => {
                                      {
                                        const $t15884_i12136 = bits_i12134;
                                        return ($t15884_i12136 / 4.50359962737e+15);
                                      }
                                    })();
                                    return { _0: $t15885_i12137, _1: rng2_i12135 };
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const t_i5178 = $p29281_i5177._0;
                            {
                              const rng2_i5179 = $p29281_i5177._1;
                              {
                                const out_i5180 = { _0: rng2_i5179, _1: t_i5178 };
                                return out_i5180;
                              }
                            }
                          }
                        }
                      })();
                      {
                        const r4 = $p29330._0;
                        {
                          const tcm = $p29330._1;
                          {
                            const $p29329 = (() => {
                              {
                                const $p29281_i5172 = (() => {
                                  {
                                    const $p15886_i12117 = (() => {
                                      {
                                        const $p15883_i1921_i12107 = Random$next_raw(r4);
                                        {
                                          const hi_i1922_i12108 = $p15883_i1921_i12107._0;
                                          {
                                            const rng2_i1923_i12109 = $p15883_i1921_i12107._1;
                                            {
                                              const $p15882_i1924_i12110 = Random$next_raw(rng2_i1923_i12109);
                                              {
                                                const lo_i1925_i12111 = $p15882_i1924_i12110._0;
                                                {
                                                  const rng3_i1926_i12112 = $p15882_i1924_i12110._1;
                                                  {
                                                    const $t15881_i1930_i12116 = (() => {
                                                      {
                                                        const $t15880_i1929_i12115 = (() => {
                                                          {
                                                            const $t15878_i1927_i12113 = march_int_and(hi_i1922_i12108, 1048575);
                                                            return ($t15878_i1927_i12113 * 4294967296);
                                                          }
                                                        })();
                                                        return ($t15880_i1929_i12115 + lo_i1925_i12111);
                                                      }
                                                    })();
                                                    return { _0: $t15881_i1930_i12116, _1: rng3_i1926_i12112 };
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const bits_i12118 = $p15886_i12117._0;
                                      {
                                        const rng2_i12119 = $p15886_i12117._1;
                                        {
                                          const $t15885_i12121 = (() => {
                                            {
                                              const $t15884_i12120 = bits_i12118;
                                              return ($t15884_i12120 / 4.50359962737e+15);
                                            }
                                          })();
                                          return { _0: $t15885_i12121, _1: rng2_i12119 };
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const t_i5173 = $p29281_i5172._0;
                                  {
                                    const rng2_i5174 = $p29281_i5172._1;
                                    {
                                      const out_i5175 = { _0: rng2_i5174, _1: t_i5173 };
                                      return out_i5175;
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const r5 = $p29329._0;
                              {
                                const tsm = $p29329._1;
                                {
                                  const $p29328 = (() => {
                                    {
                                      const $p29281_i5167 = (() => {
                                        {
                                          const $p15886_i12101 = (() => {
                                            {
                                              const $p15883_i1921_i12091 = Random$next_raw(r5);
                                              {
                                                const hi_i1922_i12092 = $p15883_i1921_i12091._0;
                                                {
                                                  const rng2_i1923_i12093 = $p15883_i1921_i12091._1;
                                                  {
                                                    const $p15882_i1924_i12094 = Random$next_raw(rng2_i1923_i12093);
                                                    {
                                                      const lo_i1925_i12095 = $p15882_i1924_i12094._0;
                                                      {
                                                        const rng3_i1926_i12096 = $p15882_i1924_i12094._1;
                                                        {
                                                          const $t15881_i1930_i12100 = (() => {
                                                            {
                                                              const $t15880_i1929_i12099 = (() => {
                                                                {
                                                                  const $t15878_i1927_i12097 = march_int_and(hi_i1922_i12092, 1048575);
                                                                  return ($t15878_i1927_i12097 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15880_i1929_i12099 + lo_i1925_i12095);
                                                            }
                                                          })();
                                                          return { _0: $t15881_i1930_i12100, _1: rng3_i1926_i12096 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i12102 = $p15886_i12101._0;
                                            {
                                              const rng2_i12103 = $p15886_i12101._1;
                                              {
                                                const $t15885_i12105 = (() => {
                                                  {
                                                    const $t15884_i12104 = bits_i12102;
                                                    return ($t15884_i12104 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15885_i12105, _1: rng2_i12103 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i5168 = $p29281_i5167._0;
                                        {
                                          const rng2_i5169 = $p29281_i5167._1;
                                          {
                                            const out_i5170 = { _0: rng2_i5169, _1: t_i5168 };
                                            return out_i5170;
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const r6 = $p29328._0;
                                    {
                                      const trings = $p29328._1;
                                      {
                                        const gap = (() => {
                                          {
                                            const $t29283_i5165 = (() => {
                                              {
                                                const $t29282_i5164 = (260. - 160.);
                                                return (ty * $t29282_i5164);
                                              }
                                            })();
                                            return (160. + $t29283_i5165);
                                          }
                                        })();
                                        {
                                          const dx = (() => {
                                            {
                                              const $t29311 = (0. - 220.);
                                              {
                                                const $t29283_i5160 = (() => {
                                                  {
                                                    const $t29282_i5159 = (220. - $t29311);
                                                    return (tx * $t29282_i5159);
                                                  }
                                                })();
                                                return ($t29311 + $t29283_i5160);
                                              }
                                            }
                                          })();
                                          {
                                            const x = (() => {
                                              {
                                                const $t29314 = (() => {
                                                  {
                                                    const $t29313 = prev.x;
                                                    return ($t29313 + dx);
                                                  }
                                                })();
                                                {
                                                  const $t29317 = (view_w - 60.);
                                                  {
                                                    const $t1601_i5154 = ($t29314 < 60.);
                                                    if ($t1601_i5154 === true) {
                                                      return 60.;
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const $t1602_i5155 = ($t29314 > $t29317);
                                                          if ($t1602_i5155 === true) {
                                                            return $t29317;
                                                          } else {
                                                            return $t29314;
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
                                                  const $t29320 = (tr * tr);
                                                  {
                                                    const $t29283_i5150 = (() => {
                                                      {
                                                        const $t29282_i5149 = (20. - 8.);
                                                        return ($t29320 * $t29282_i5149);
                                                      }
                                                    })();
                                                    return (8. + $t29283_i5150);
                                                  }
                                                }
                                              })();
                                              {
                                                const cm = (() => {
                                                  {
                                                    const $t29283_i5145 = (() => {
                                                      {
                                                        const $t29282_i5144 = (5.2 - 2.8);
                                                        return (tcm * $t29282_i5144);
                                                      }
                                                    })();
                                                    return (2.8 + $t29283_i5145);
                                                  }
                                                })();
                                                {
                                                  const sm = (() => {
                                                    {
                                                      const $t29283_i5140 = (() => {
                                                        {
                                                          const $t29282_i5139 = (1.6 - 0.7);
                                                          return (tsm * $t29282_i5139);
                                                        }
                                                      })();
                                                      return (0.7 + $t29283_i5140);
                                                    }
                                                  })();
                                                  {
                                                    const cap = (r * cm);
                                                    {
                                                      const $t29325 = (() => {
                                                        {
                                                          const $t29284_i5134 = (trings < 0.55);
                                                          if ($t29284_i5134 === true) {
                                                            return 1;
                                                          } else {
                                                            return (() => {
                                                              {
                                                                const $t29285_i5135 = (trings < 0.85);
                                                                if ($t29285_i5135 === true) {
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
                                                        const orbits = Perihelion$Level$make_orbits(cap, sm, $t29325);
                                                        {
                                                          const s = (() => {
                                                            {
                                                              const $t29327 = (() => {
                                                                {
                                                                  const $t29326 = prev.y;
                                                                  return ($t29326 - gap);
                                                                }
                                                              })();
                                                              return ({ x: x, y: $t29327, radius: r, capture_radius: cap, speed_mult: sm, orbits: orbits });
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
        const $t29334 = (view_w / 2.);
        {
          const $t29335 = ({ radius: 54., speed_mult: 1. });
          {
            const $t29336 = { $: "Nil" };
            {
              const $t29337 = { $: "Cons", _0: $t29335, _1: $t29336 };
              return ({ x: $t29334, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29337 });
            }
          }
        }
      }
    })();
    {
      const $p29342 = Perihelion$Level$next_star(rng, first, view_w);
      {
        const s2 = $p29342._0;
        {
          const rng2 = $p29342._1;
          {
            const $p29341 = Perihelion$Level$next_star(rng2, s2, view_w);
            {
              const s3 = $p29341._0;
              {
                const rng3 = $p29341._1;
                {
                  const $t29338 = { $: "Nil" };
                  {
                    const $t29339 = { $: "Cons", _0: s3, _1: $t29338 };
                    {
                      const $t29340 = { $: "Cons", _0: s2, _1: $t29339 };
                      {
                        const stars = { $: "Cons", _0: first, _1: $t29340 };
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
    const $t29354 = (() => {
      {
        const $t29352 = (() => {
          {
            const x_i5257 = (() => {
              {
                const $t29348_i5256 = (() => {
                  {
                    const $t29347_i5255 = (() => {
                      {
                        const $t29345_i5253 = (() => {
                          {
                            const $t29343_i5251 = (sx * 12.9898);
                            {
                              const $t29344_i5252 = (sy * 78.233);
                              return ($t29343_i5251 + $t29344_i5252);
                            }
                          }
                        })();
                        {
                          const $t29346_i5254 = (seed * 37.719);
                          return ($t29345_i5253 + $t29346_i5254);
                        }
                      }
                    })();
                    return Math.sin($t29347_i5255);
                  }
                })();
                return ($t29348_i5256 * 43758.5453);
              }
            })();
            {
              const $t29349_i5258 = (() => {
                {
                  const $t1603_i12199 = Math.floor(x_i5257);
                  return $t1603_i12199;
                }
              })();
              return (x_i5257 - $t29349_i5258);
            }
          }
        })();
        return ($t29352 > 0.55);
      }
    })();
    if ($t29354 === true) {
      return { $: "None" };
    } else {
      return (() => {
        {
          const jx = (() => {
            {
              const $t29358 = (() => {
                {
                  const $t29357 = (() => {
                    {
                      const $t29356 = (() => {
                        {
                          const $t29355 = (sx + 1.);
                          {
                            const x_i5246 = (() => {
                              {
                                const $t29348_i5245 = (() => {
                                  {
                                    const $t29347_i5244 = (() => {
                                      {
                                        const $t29345_i5242 = (() => {
                                          {
                                            const $t29343_i5240 = ($t29355 * 12.9898);
                                            {
                                              const $t29344_i5241 = (sy * 78.233);
                                              return ($t29343_i5240 + $t29344_i5241);
                                            }
                                          }
                                        })();
                                        {
                                          const $t29346_i5243 = (seed * 37.719);
                                          return ($t29345_i5242 + $t29346_i5243);
                                        }
                                      }
                                    })();
                                    return Math.sin($t29347_i5244);
                                  }
                                })();
                                return ($t29348_i5245 * 43758.5453);
                              }
                            })();
                            {
                              const $t29349_i5247 = (() => {
                                {
                                  const $t1603_i12196 = Math.floor(x_i5246);
                                  return $t1603_i12196;
                                }
                              })();
                              return (x_i5246 - $t29349_i5247);
                            }
                          }
                        }
                      })();
                      return ($t29356 - 0.5);
                    }
                  })();
                  return ($t29357 * 2.);
                }
              })();
              return ($t29358 * 90.);
            }
          })();
          {
            const jy = (() => {
              {
                const $t29363 = (() => {
                  {
                    const $t29362 = (() => {
                      {
                        const $t29361 = (() => {
                          {
                            const $t29360 = (sy + 1.);
                            {
                              const x_i5235 = (() => {
                                {
                                  const $t29348_i5234 = (() => {
                                    {
                                      const $t29347_i5233 = (() => {
                                        {
                                          const $t29345_i5231 = (() => {
                                            {
                                              const $t29343_i5229 = (sx * 12.9898);
                                              {
                                                const $t29344_i5230 = ($t29360 * 78.233);
                                                return ($t29343_i5229 + $t29344_i5230);
                                              }
                                            }
                                          })();
                                          {
                                            const $t29346_i5232 = (seed * 37.719);
                                            return ($t29345_i5231 + $t29346_i5232);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29347_i5233);
                                    }
                                  })();
                                  return ($t29348_i5234 * 43758.5453);
                                }
                              })();
                              {
                                const $t29349_i5236 = (() => {
                                  {
                                    const $t1603_i12193 = Math.floor(x_i5235);
                                    return $t1603_i12193;
                                  }
                                })();
                                return (x_i5235 - $t29349_i5236);
                              }
                            }
                          }
                        })();
                        return ($t29361 - 0.5);
                      }
                    })();
                    return ($t29362 * 2.);
                  }
                })();
                return ($t29363 * 90.);
              }
            })();
            {
              const rt = (() => {
                {
                  const $t29365 = (sx + 2.);
                  {
                    const x_i5224 = (() => {
                      {
                        const $t29348_i5223 = (() => {
                          {
                            const $t29347_i5222 = (() => {
                              {
                                const $t29345_i5220 = (() => {
                                  {
                                    const $t29343_i5218 = ($t29365 * 12.9898);
                                    {
                                      const $t29344_i5219 = (sy * 78.233);
                                      return ($t29343_i5218 + $t29344_i5219);
                                    }
                                  }
                                })();
                                {
                                  const $t29346_i5221 = (seed * 37.719);
                                  return ($t29345_i5220 + $t29346_i5221);
                                }
                              }
                            })();
                            return Math.sin($t29347_i5222);
                          }
                        })();
                        return ($t29348_i5223 * 43758.5453);
                      }
                    })();
                    {
                      const $t29349_i5225 = (() => {
                        {
                          const $t1603_i12190 = Math.floor(x_i5224);
                          return $t1603_i12190;
                        }
                      })();
                      return (x_i5224 - $t29349_i5225);
                    }
                  }
                }
              })();
              {
                const r = (() => {
                  {
                    const $t29368 = (rt * rt);
                    {
                      const $t29351_i5214 = (() => {
                        {
                          const $t29350_i5213 = (700. - 240.);
                          return ($t29368 * $t29350_i5213);
                        }
                      })();
                      return (240. + $t29351_i5214);
                    }
                  }
                })();
                {
                  const strength = (() => {
                    {
                      const $t29371 = (() => {
                        {
                          const $t29370 = (() => {
                            {
                              const $t29369 = (sy + 2.);
                              {
                                const x_i5208 = (() => {
                                  {
                                    const $t29348_i5207 = (() => {
                                      {
                                        const $t29347_i5206 = (() => {
                                          {
                                            const $t29345_i5204 = (() => {
                                              {
                                                const $t29343_i5202 = (sx * 12.9898);
                                                {
                                                  const $t29344_i5203 = ($t29369 * 78.233);
                                                  return ($t29343_i5202 + $t29344_i5203);
                                                }
                                              }
                                            })();
                                            {
                                              const $t29346_i5205 = (seed * 37.719);
                                              return ($t29345_i5204 + $t29346_i5205);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29347_i5206);
                                      }
                                    })();
                                    return ($t29348_i5207 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29349_i5209 = (() => {
                                    {
                                      const $t1603_i12187 = Math.floor(x_i5208);
                                      return $t1603_i12187;
                                    }
                                  })();
                                  return (x_i5208 - $t29349_i5209);
                                }
                              }
                            }
                          })();
                          return (0.65 * $t29370);
                        }
                      })();
                      return (0.35 + $t29371);
                    }
                  })();
                  {
                    const $t29374 = (() => {
                      {
                        const $t29372 = (sx + jx);
                        {
                          const $t29373 = (sy + jy);
                          return ({ x: $t29372, y: $t29373, radius: r, strength: strength });
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29374 };
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
      const $f29407 = stars._0;
      const $f29408 = stars._1;
      {
        const rest = $f29408;
        {
          const s = $f29407;
          {
            const $t29405 = (() => {
              {
                const $t29403 = s.x;
                {
                  const $t29404 = s.y;
                  return Perihelion$Nebula$star_cloud($t29403, $t29404, seed);
                }
              }
            })();
            {
              let acc2;
              switch ($t29405.$) {
                case "None": {
                  acc2 = acc;
                  break;
                }
                case "Some": {
                  const $f29406 = $t29405._0;
                  acc2 = (() => {
                    {
                      const c = $f29406;
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
      const $f29421 = stars._0;
      const $f29422 = stars._1;
      {
        const rest = $f29422;
        {
          const s = $f29421;
          {
            const $t29420 = (() => {
              {
                const $t29415_i5291 = (() => {
                  {
                    const $t29413_i5289 = s.y;
                    {
                      const $t29414_i5290 = (cam_y - margin);
                      return ($t29413_i5289 >= $t29414_i5290);
                    }
                  }
                })();
                {
                  const $t29419_i5295 = (() => {
                    {
                      const $t29416_i5292 = s.y;
                      {
                        const $t29418_i5294 = (() => {
                          {
                            const $t29417_i5293 = (cam_y + view_h);
                            return ($t29417_i5293 + margin);
                          }
                        })();
                        return ($t29416_i5292 <= $t29418_i5294);
                      }
                    }
                  })();
                  return ($t29415_i5291 && $t29419_i5295);
                }
              }
            })();
            {
              let acc2;
              if ($t29420 === true) {
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
    const $t29432 = (stars_chained > 0);
    {
      const $t29435 = (() => {
        {
          const $t29434 = march_int_mod(stars_chained, 10);
          return ($t29434 === 0);
        }
      })();
      return ($t29432 && $t29435);
    }
  }
}
const Perihelion$Upgrades$is_milestone$clo = { _0: ($_, stars_chained) => Perihelion$Upgrades$is_milestone(stars_chained) };

function Perihelion$Upgrades$milestone_pool(owned) {
  {
    const $t29437 = (() => {
      {
        const $t29436 = { $: "Homing" };
        return { $: "OffenseWeapon", _0: $t29436 };
      }
    })();
    {
      const $t29439 = (() => {
        {
          const $t29438 = { $: "Spread" };
          return { $: "OffenseWeapon", _0: $t29438 };
        }
      })();
      {
        const $t29440 = { $: "Nil" };
        {
          const $t29441 = { $: "Cons", _0: $t29439, _1: $t29440 };
          {
            const all_weapons = { $: "Cons", _0: $t29437, _1: $t29441 };
            {
              const $t29445 = { $: "$Clo_$lam29442$3817", _0: $lam29442$apply$3817, _1: owned };
              {
                const unowned_weapons = (() => {
                  {
                    const pred_i5302 = $t29445;
                    {
                      const go_i5303 = { $: "$Clo_go$4823", _0: go$apply$4823, _1: pred_i5302 };
                      {
                        const $t323_i5304 = { $: "Nil" };
                        return go$apply$4823(go_i5303, all_weapons, $t323_i5304);
                      }
                    }
                  }
                })();
                {
                  const $t29446 = { $: "OffenseFireRate" };
                  {
                    const $t29447 = { $: "DefenseBulletWard" };
                    {
                      const $t29448 = { $: "DefenseDeflector" };
                      {
                        const $t29449 = { $: "DefenseShield" };
                        {
                          const $t29451 = (() => {
                            {
                              const $t29450 = { $: "StarThrust" };
                              return { $: "SpecialItem", _0: $t29450 };
                            }
                          })();
                          {
                            const $t29453 = (() => {
                              {
                                const $t29452 = { $: "StarJump" };
                                return { $: "SpecialItem", _0: $t29452 };
                              }
                            })();
                            {
                              const $t29455 = (() => {
                                {
                                  const $t29454 = { $: "TrajectoryPreview" };
                                  return { $: "SpecialItem", _0: $t29454 };
                                }
                              })();
                              {
                                const $t29456 = { $: "Nil" };
                                {
                                  const $t29457 = { $: "Cons", _0: $t29455, _1: $t29456 };
                                  {
                                    const $t29458 = { $: "Cons", _0: $t29453, _1: $t29457 };
                                    {
                                      const $t29459 = { $: "Cons", _0: $t29451, _1: $t29458 };
                                      {
                                        const $t29460 = { $: "Cons", _0: $t29449, _1: $t29459 };
                                        {
                                          const $t29461 = { $: "Cons", _0: $t29448, _1: $t29460 };
                                          {
                                            const $t29462 = { $: "Cons", _0: $t29447, _1: $t29461 };
                                            {
                                              const $t29463 = { $: "Cons", _0: $t29446, _1: $t29462 };
                                              {
                                                const go_i5299 = { $: "$Clo_go$4821", _0: go$apply$4821 };
                                                {
                                                  const $t282_i5300 = (() => {
                                                    {
                                                      const go_i12202 = { $: "$Clo_go$5277", _0: go$apply$5277 };
                                                      {
                                                        const $t274_i12203 = { $: "Nil" };
                                                        return go$apply$5277(go_i12202, unowned_weapons, $t274_i12203);
                                                      }
                                                    }
                                                  })();
                                                  return go$apply$4821(go_i5299, $t282_i5300, $t29463);
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t29464 = (() => {
      {
        const go_i5311 = { $: "$Clo_go$4826", _0: go$apply$4826 };
        {
          const $t529_i5312 = { $: "Nil" };
          return go$apply$4826(go_i5311, xs, idx, $t529_i5312);
        }
      }
    })();
    {
      const $t29465 = (idx + 1);
      {
        const $t29466 = List$drop$List_UpgradeKind$Int(xs, $t29465);
        {
          const go_i5307 = { $: "$Clo_go$4821", _0: go$apply$4821 };
          {
            const $t282_i5308 = (() => {
              {
                const go_i12205 = { $: "$Clo_go$5277", _0: go$apply$5277 };
                {
                  const $t274_i12206 = { $: "Nil" };
                  return go$apply$5277(go_i12205, $t29464, $t274_i12206);
                }
              }
            })();
            return go$apply$4821(go_i5307, $t282_i5308, $t29466);
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$remove_upgrade_at$clo = { _0: ($_, xs, idx) => Perihelion$Upgrades$remove_upgrade_at(xs, idx) };

function Perihelion$Upgrades$pick_and_remove(rng, pool) {
  {
    const $p29470 = (() => {
      {
        const $p29281_i5129_i12208 = (() => {
          {
            const $p15886_i12761 = (() => {
              {
                const $p15883_i1921_i12752 = Random$next_raw(rng);
                {
                  const hi_i1922_i12753 = $p15883_i1921_i12752._0;
                  {
                    const rng2_i1923_i12754 = $p15883_i1921_i12752._1;
                    {
                      const $p15882_i1924_i12755 = Random$next_raw(rng2_i1923_i12754);
                      {
                        const lo_i1925_i12756 = $p15882_i1924_i12755._0;
                        {
                          const rng3_i1926_i12757 = $p15882_i1924_i12755._1;
                          {
                            const $t15881_i1930_i12760 = (() => {
                              {
                                const $t15880_i1929_i12759 = (() => {
                                  {
                                    const $t15878_i1927_i12758 = march_int_and(hi_i1922_i12753, 1048575);
                                    return ($t15878_i1927_i12758 * 4294967296);
                                  }
                                })();
                                return ($t15880_i1929_i12759 + lo_i1925_i12756);
                              }
                            })();
                            return { _0: $t15881_i1930_i12760, _1: rng3_i1926_i12757 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i12762 = $p15886_i12761._0;
              {
                const rng2_i12763 = $p15886_i12761._1;
                {
                  const $t15885_i12765 = (() => {
                    {
                      const $t15884_i12764 = bits_i12762;
                      return ($t15884_i12764 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15885_i12765, _1: rng2_i12763 };
                }
              }
            }
          }
        })();
        {
          const t_i5130_i12209 = $p29281_i5129_i12208._0;
          {
            const rng2_i5131_i12210 = $p29281_i5129_i12208._1;
            {
              const out_i5132_i12211 = { _0: rng2_i5131_i12210, _1: t_i5130_i12209 };
              return out_i5132_i12211;
            }
          }
        }
      }
    })();
    {
      const rng2 = $p29470._0;
      {
        const t = $p29470._1;
        {
          const n = (() => {
            {
              const go_i5314 = { $: "$Clo_go$4829", _0: go$apply$4829 };
              return go$apply$4829(go_i5314, pool, 0);
            }
          })();
          {
            const idx = (() => {
              {
                const $t29468 = (() => {
                  {
                    const $t29467 = n;
                    return (t * $t29467);
                  }
                })();
                return Math.trunc($t29468);
              }
            })();
            {
              const clamped = (() => {
                {
                  const $t29469 = (idx >= n);
                  if ($t29469 === true) {
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
    const $t29473 = (() => {
      {
        const $t29471 = (n === 0);
        {
          let $t29472;
          switch (pool.$) {
            case "Nil": {
              $t29472 = true;
              break;
            }
            default: {
              $t29472 = false;
              break;
            }
          }
          return ($t29471 || $t29472);
        }
      }
    })();
    if ($t29473 === true) {
      return { _0: rng, _1: acc };
    } else {
      return (() => {
        {
          const $p29476 = Perihelion$Upgrades$pick_and_remove(rng, pool);
          {
            const rng2 = $p29476._0;
            {
              const picked = $p29476._1;
              {
                const rest = $p29476._2;
                {
                  const $t29474 = (n - 1);
                  {
                    const $t29475 = (() => {
                      return { $: "Cons", _0: picked, _1: acc };
                    })();
                    return Perihelion$Upgrades$draw_n(rng2, rest, $t29474, $t29475);
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
        const $t29477 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        {
          const $t29478 = { $: "Nil" };
          return Perihelion$Upgrades$draw_n(rng, $t29477, 3, $t29478);
        }
      }
      break;
    }
    case "Some": {
      const $f29487 = current_special._0;
      {
        const k = $f29487;
        {
          const $t29479 = Perihelion$Upgrades$milestone_pool(owned_weapons);
          {
            const $t29482 = (() => {
              return { $: "$Clo_$lam29480$3818", _0: $lam29480$apply$3818, _1: k };
            })();
            {
              const pool = (() => {
                {
                  const pred_i5319 = $t29482;
                  {
                    const go_i5320 = { $: "$Clo_go$4823", _0: go$apply$4823, _1: pred_i5319 };
                    {
                      const $t323_i5321 = { $: "Nil" };
                      return go$apply$4823(go_i5320, $t29479, $t323_i5321);
                    }
                  }
                }
              })();
              {
                const $p29486 = (() => {
                  {
                    const $t29483 = { $: "Nil" };
                    return Perihelion$Upgrades$draw_n(rng, pool, 2, $t29483);
                  }
                })();
                {
                  const rng2 = $p29486._0;
                  {
                    const two = $p29486._1;
                    {
                      const $t29484 = { $: "SpecialItem", _0: k };
                      {
                        const $t29485 = (() => {
                          return { $: "Cons", _0: $t29484, _1: two };
                        })();
                        return { _0: rng2, _1: $t29485 };
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
    const $p29489 = (() => {
      {
        const $t29488 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        return Perihelion$Upgrades$pick_and_remove(rng, $t29488);
      }
    })();
    {
      const rng2 = $p29489._0;
      {
        const picked = $p29489._1;
        return { _0: rng2, _1: picked };
      }
    }
  }
}
const Perihelion$Upgrades$roll_one$clo = { _0: ($_, rng, owned_weapons, current_special) => Perihelion$Upgrades$roll_one(rng, owned_weapons, current_special) };

function boot_seed() {
  {
    const $t29492 = (() => {
      {
        const $t29491 = (() => {
          {
            const $t29490 = {  };
            return march_unix_time();
          }
        })();
        return ($t29491 * 1000000.);
      }
    })();
    return Math.trunc($t29492);
  }
}
const boot_seed$clo = { _0: ($_) => boot_seed() };

function spawn_burst_particles(x, y, t, i, acc) {
  {
    const $t29503 = (i >= 10);
    if ($t29503 === true) {
      return acc;
    } else {
      return (() => {
        {
          const seed = (() => {
            {
              const $t29505 = (() => {
                {
                  const $t29504 = i;
                  return ($t29504 * 7.);
                }
              })();
              return (t + $t29505);
            }
          })();
          {
            const a = (() => {
              {
                const $t29506 = (() => {
                  {
                    const x_i5349 = (() => {
                      {
                        const $t29500_i5348 = (() => {
                          {
                            const $t29499_i5347 = (() => {
                              {
                                const $t29497_i5345 = (seed * 12.9898);
                                {
                                  const $t29498_i5346 = (1. * 78.233);
                                  return ($t29497_i5345 + $t29498_i5346);
                                }
                              }
                            })();
                            return Math.sin($t29499_i5347);
                          }
                        })();
                        return ($t29500_i5348 * 43758.5453);
                      }
                    })();
                    {
                      const $t29501_i5350 = (() => {
                        {
                          const $t1603_i12219 = Math.floor(x_i5349);
                          return $t1603_i12219;
                        }
                      })();
                      return (x_i5349 - $t29501_i5350);
                    }
                  }
                })();
                return ($t29506 * 6.28318530718);
              }
            })();
            {
              const speed = (() => {
                {
                  const $t29509 = (() => {
                    {
                      const $t29508 = (() => {
                        {
                          const x_i5341 = (() => {
                            {
                              const $t29500_i5340 = (() => {
                                {
                                  const $t29499_i5339 = (() => {
                                    {
                                      const $t29497_i5337 = (seed * 12.9898);
                                      {
                                        const $t29498_i5338 = (2. * 78.233);
                                        return ($t29497_i5337 + $t29498_i5338);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29499_i5339);
                                }
                              })();
                              return ($t29500_i5340 * 43758.5453);
                            }
                          })();
                          {
                            const $t29501_i5342 = (() => {
                              {
                                const $t1603_i12216 = Math.floor(x_i5341);
                                return $t1603_i12216;
                              }
                            })();
                            return (x_i5341 - $t29501_i5342);
                          }
                        }
                      })();
                      return ($t29508 * 90.);
                    }
                  })();
                  return (40. + $t29509);
                }
              })();
              {
                const life = (() => {
                  {
                    const $t29513 = (() => {
                      {
                        const $t29512 = (() => {
                          {
                            const $t29511 = (() => {
                              {
                                const x_i5333 = (() => {
                                  {
                                    const $t29500_i5332 = (() => {
                                      {
                                        const $t29499_i5331 = (() => {
                                          {
                                            const $t29497_i5329 = (seed * 12.9898);
                                            {
                                              const $t29498_i5330 = (3. * 78.233);
                                              return ($t29497_i5329 + $t29498_i5330);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29499_i5331);
                                      }
                                    })();
                                    return ($t29500_i5332 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29501_i5334 = (() => {
                                    {
                                      const $t1603_i12213 = Math.floor(x_i5333);
                                      return $t1603_i12213;
                                    }
                                  })();
                                  return (x_i5333 - $t29501_i5334);
                                }
                              }
                            })();
                            return (0.4 * $t29511);
                          }
                        })();
                        return (0.6 + $t29512);
                      }
                    })();
                    return (0.5 * $t29513);
                  }
                })();
                {
                  const p = (() => {
                    {
                      const $t29515 = (() => {
                        {
                          const $t29514 = Math.cos(a);
                          return ($t29514 * speed);
                        }
                      })();
                      {
                        const $t29517 = (() => {
                          {
                            const $t29516 = Math.sin(a);
                            return ($t29516 * speed);
                          }
                        })();
                        return ({ x: x, y: y, vx: $t29515, vy: $t29517, life: life, max_life: life });
                      }
                    }
                  })();
                  {
                    const $t29518 = (i + 1);
                    {
                      const $t29519 = { $: "Cons", _0: p, _1: acc };
                      return spawn_burst_particles(x, y, t, $t29518, $t29519);
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
      const $f29522 = bursts._0;
      const $f29523 = bursts._1;
      {
        const rest = (() => {
          return $f29523;
        })();
        {
          const pt = (() => {
            return $f29522;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const $t29520 = spawn_burst_particles(x, y, t, 0, acc);
                return spawn_bursts(rest, t, $t29520);
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
      const $f29549 = flash._0;
      {
        const f = $f29549;
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const tr2 = (tr - dt_s);
                {
                  const $t29546 = (tr2 > 0.);
                  if ($t29546 === true) {
                    return (() => {
                      {
                        const $t29547 = { _0: x, _1: y, _2: tr2 };
                        return { $: "Some", _0: $t29547 };
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
        const $t29550 = fx.t;
        return ($t29550 + dt_s);
      }
    })();
    {
      const $t29551 = (() => {
        {
          const $t30120_i5376 = game.phase;
          switch ($t30120_i5376.$) {
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
        if ($t29551 === true) {
          trail2 = (() => {
            {
              const $t29552 = fx.trail;
              {
                const $t29553 = game.ball_x;
                {
                  const $t29554 = game.ball_y;
                  {
                    const $t29555 = { _0: $t29553, _1: $t29554 };
                    {
                      const $t29544_i5373 = { $: "Cons", _0: $t29555, _1: $t29552 };
                      {
                        const go_i12231 = { $: "$Clo_go$4835", _0: go$apply$4835 };
                        {
                          const $t529_i12232 = { $: "Nil" };
                          return go$apply$4835(go_i12231, $t29544_i5373, 14, $t529_i12232);
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
          const $t29556 = game.fx_bursts;
          {
            const $t29557 = fx.particles;
            {
              const $t29558 = (() => {
                return spawn_bursts($t29556, t2, $t29557);
              })();
              {
                const particles2 = (() => {
                  {
                    const $t29539_i5368 = { $: "$Clo_$lam29538$3820", _0: $lam29538$apply$3820, _1: dt_s };
                    {
                      const $t29540_i5369 = (() => {
                        {
                          const f_i12226 = $t29539_i5368;
                          {
                            const go_i12227 = { $: "$Clo_go$4833", _0: go$apply$4833, _1: f_i12226 };
                            {
                              const $t291_i12228 = { $: "Nil" };
                              return go$apply$4833(go_i12227, $t29558, $t291_i12228);
                            }
                          }
                        }
                      })();
                      {
                        const $t29543_i5370 = { $: "$Clo_$lam29541$3821", _0: $lam29541$apply$3821 };
                        {
                          const pred_i12222 = $t29543_i5370;
                          {
                            const go_i12223 = { $: "$Clo_go$4831", _0: go$apply$4831, _1: pred_i12222 };
                            {
                              const $t323_i12224 = { $: "Nil" };
                              return go$apply$4831(go_i12223, $t29540_i5369, $t323_i12224);
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
                      const $t29559 = fx.flash;
                      return step_flash($t29559, dt_s);
                    }
                  })();
                  {
                    const flash2 = (() => {
                      {
                        const $t29560 = game.capture_flash;
                        switch ($t29560.$) {
                          case "None": {
                            return flash1;
                            break;
                          }
                          case "Some": {
                            const $f29564 = $t29560._0;
                            {
                              const pt = (() => {
                                return $f29564;
                              })();
                              {
                                const x = pt._0;
                                {
                                  const y = pt._1;
                                  {
                                    const $t29562 = { _0: x, _1: y, _2: 0.45 };
                                    return { $: "Some", _0: $t29562 };
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
      const $f29574 = trail._0;
      const $f29575 = trail._1;
      {
        const rest = (() => {
          return $f29575;
        })();
        {
          const pt = (() => {
            return $f29574;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const f = (() => {
                  {
                    const $t29567 = (() => {
                      {
                        const $t29565 = i;
                        {
                          const $t29566 = n;
                          return ($t29565 / $t29566);
                        }
                      }
                    })();
                    return (1. - $t29567);
                  }
                })();
                (() => {
                  {
                    const $t29568 = (f * 0.28);
                    return Canvas$set_global_alpha(ctx, $t29568);
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
                    const $t29570 = (() => {
                      {
                        const $t29569 = (2.5 * f);
                        return (1. + $t29569);
                      }
                    })();
                    return Canvas$arc(ctx, x, y, $t29570, 0., 6.28318530718);
                  }
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t29572 = (i + 1);
                  return draw_trail(ctx, rest, $t29572, n);
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
      const $f29587 = particles._0;
      const $f29588 = particles._1;
      {
        const rest = (() => {
          return $f29588;
        })();
        {
          const p = (() => {
            return $f29587;
          })();
          {
            const f = (() => {
              {
                const $t29580 = p.life;
                {
                  const $t29581 = p.max_life;
                  return ($t29580 / $t29581);
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
                const $t29582 = p.x;
                {
                  const $t29583 = p.y;
                  {
                    const $t29585 = (() => {
                      {
                        const $t29584 = (1.5 * f);
                        return (0.5 + $t29584);
                      }
                    })();
                    return Canvas$arc(ctx, $t29582, $t29583, $t29585, 0., 6.28318530718);
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
      const $f29603 = flash._0;
      {
        const f = (() => {
          return $f29603;
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
                    const $t29594 = (tr / 0.45);
                    return (1. - $t29594);
                  }
                })();
                {
                  const r = (() => {
                    {
                      const $t29595 = (prog * 60.);
                      return (8. + $t29595);
                    }
                  })();
                  (() => {
                    {
                      const $t29597 = (() => {
                        {
                          const $t29596 = (1. - prog);
                          return ($t29596 * 0.7);
                        }
                      })();
                      return Canvas$set_global_alpha(ctx, $t29597);
                    }
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#ffffff");
                  })();
                  (() => {
                    {
                      const $t29600 = (() => {
                        {
                          const $t29599 = (() => {
                            {
                              const $t29598 = (1. - prog);
                              return (2.5 * $t29598);
                            }
                          })();
                          return ($t29599 + 0.5);
                        }
                      })();
                      return Canvas$set_line_width(ctx, $t29600);
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

function draw_pulse_ring(ctx, s, pulse) {
  (() => {
    {
      const $t29638 = (0.1 * pulse);
      return Canvas$set_global_alpha(ctx, $t29638);
    }
  })();
  (() => {
    return Canvas$set_stroke_style(ctx, "#cfcfcf");
  })();
  (() => {
    {
      const $t29640 = (() => {
        {
          const $t29639 = (0.6 * pulse);
          return (1. + $t29639);
        }
      })();
      return Canvas$set_line_width(ctx, $t29640);
    }
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t29641 = s.x;
      {
        const $t29642 = s.y;
        {
          const $t29643 = s.capture_radius;
          return Canvas$arc(ctx, $t29641, $t29642, $t29643, 0., 6.28318530718);
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
      const $t29646 = (() => {
        {
          const $t29645 = (0.035 * pulse);
          return (0.025 + $t29645);
        }
      })();
      return Canvas$set_global_alpha(ctx, $t29646);
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
      const $t29647 = s.x;
      {
        const $t29648 = s.y;
        {
          const $t29652 = (() => {
            {
              const $t29649 = s.radius;
              {
                const $t29651 = (() => {
                  {
                    const $t29650 = (0.9 * pulse);
                    return (1.6 + $t29650);
                  }
                })();
                return ($t29649 * $t29651);
              }
            }
          })();
          return Canvas$arc(ctx, $t29647, $t29648, $t29652, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_pulse_halo$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_halo(ctx, s, pulse) };

function draw_pulse_particle(ctx, s, t, n, i) {
  {
    const $t29654 = (i >= n);
    if ($t29654 === true) {
      return {  };
    } else {
      return (() => {
        {
          const a = (() => {
            {
              const $t29658 = (() => {
                {
                  const $t29656 = (() => {
                    {
                      const $t29655 = (() => {
                        {
                          const $t29637_i5443 = (() => {
                            {
                              const $t29636_i5442 = (() => {
                                {
                                  const $t29633_i5439 = (() => {
                                    {
                                      const $t29632_i5438 = s.x;
                                      return ($t29632_i5438 + 5.);
                                    }
                                  })();
                                  {
                                    const $t29635_i5441 = (() => {
                                      {
                                        const $t29634_i5440 = s.y;
                                        return ($t29634_i5440 + 5.);
                                      }
                                    })();
                                    {
                                      const x_i12248 = (() => {
                                        {
                                          const $t29500_i12247 = (() => {
                                            {
                                              const $t29499_i12246 = (() => {
                                                {
                                                  const $t29497_i12244 = ($t29633_i5439 * 12.9898);
                                                  {
                                                    const $t29498_i12245 = ($t29635_i5441 * 78.233);
                                                    return ($t29497_i12244 + $t29498_i12245);
                                                  }
                                                }
                                              })();
                                              return Math.sin($t29499_i12246);
                                            }
                                          })();
                                          return ($t29500_i12247 * 43758.5453);
                                        }
                                      })();
                                      {
                                        const $t29501_i12250 = (() => {
                                          {
                                            const $t1603_i5323_i12249 = Math.floor(x_i12248);
                                            return $t1603_i5323_i12249;
                                          }
                                        })();
                                        return (x_i12248 - $t29501_i12250);
                                      }
                                    }
                                  }
                                }
                              })();
                              return ($t29636_i5442 * 2.4);
                            }
                          })();
                          return (0.4 + $t29637_i5443);
                        }
                      })();
                      return (t * $t29655);
                    }
                  })();
                  {
                    const $t29657 = (() => {
                      {
                        const $t29623_i5435 = (() => {
                          {
                            const $t29620_i5432 = (() => {
                              {
                                const $t29619_i5431 = s.x;
                                return ($t29619_i5431 + 3.);
                              }
                            })();
                            {
                              const $t29622_i5434 = (() => {
                                {
                                  const $t29621_i5433 = s.y;
                                  return ($t29621_i5433 + 3.);
                                }
                              })();
                              {
                                const x_i12239 = (() => {
                                  {
                                    const $t29500_i12238 = (() => {
                                      {
                                        const $t29499_i12237 = (() => {
                                          {
                                            const $t29497_i12235 = ($t29620_i5432 * 12.9898);
                                            {
                                              const $t29498_i12236 = ($t29622_i5434 * 78.233);
                                              return ($t29497_i12235 + $t29498_i12236);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29499_i12237);
                                      }
                                    })();
                                    return ($t29500_i12238 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29501_i12241 = (() => {
                                    {
                                      const $t1603_i5323_i12240 = Math.floor(x_i12239);
                                      return $t1603_i5323_i12240;
                                    }
                                  })();
                                  return (x_i12239 - $t29501_i12241);
                                }
                              }
                            }
                          }
                        })();
                        return ($t29623_i5435 * 6.28318530718);
                      }
                    })();
                    return ($t29656 + $t29657);
                  }
                }
              })();
              {
                const $t29663 = (() => {
                  {
                    const $t29659 = i;
                    {
                      const $t29662 = (() => {
                        {
                          const $t29661 = n;
                          return (6.28318530718 / $t29661);
                        }
                      })();
                      return ($t29659 * $t29662);
                    }
                  }
                })();
                return ($t29658 + $t29663);
              }
            }
          })();
          {
            const r = (() => {
              {
                const $t29664 = s.radius;
                return ($t29664 * 1.8);
              }
            })();
            {
              const px = (() => {
                {
                  const $t29665 = s.x;
                  {
                    const $t29667 = (() => {
                      {
                        const $t29666 = Math.cos(a);
                        return ($t29666 * r);
                      }
                    })();
                    return ($t29665 + $t29667);
                  }
                }
              })();
              {
                const py = (() => {
                  {
                    const $t29668 = s.y;
                    {
                      const $t29670 = (() => {
                        {
                          const $t29669 = Math.sin(a);
                          return ($t29669 * r);
                        }
                      })();
                      return ($t29668 + $t29670);
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
                  const $t29672 = (i + 1);
                  return draw_pulse_particle(ctx, s, t, n, $t29672);
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
      const $f29681 = orbits._0;
      const $f29682 = orbits._1;
      {
        const $jp_clo29688 = (() => {
          return { $: "$Clo_$jp29687$3824", _0: $jp29687$apply$3824, _1: $f29681, _2: $f29682, _3: ctx, _4: s };
        })();
        switch ($f29682.$) {
          case "Nil": {
            {
              const o = $f29681;
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
                  const $t29673 = s.x;
                  {
                    const $t29674 = s.y;
                    {
                      const $t29675 = o.radius;
                      return Canvas$arc(ctx, $t29673, $t29674, $t29675, 0., 6.28318530718);
                    }
                  }
                }
              })();
              return Canvas$stroke(ctx);
            }
            break;
          }
          default: {
            return $jp29687$apply$3824($jp_clo29688);
          }
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
      const $f29704 = aim._0;
      {
        const a = (() => {
          return $f29704;
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
                      const $t29691 = s.x;
                      return ($t29691 - px);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t29692 = s.y;
                        return ($t29692 - py);
                      }
                    })();
                    {
                      const range = (() => {
                        {
                          const $t29693 = s.capture_radius;
                          return ($t29693 * 4.);
                        }
                      })();
                      {
                        const $t29697 = (() => {
                          {
                            const $t29696 = (() => {
                              {
                                const $t29694 = (vx * dx);
                                {
                                  const $t29695 = (vy * dy);
                                  return ($t29694 + $t29695);
                                }
                              }
                            })();
                            return ($t29696 > 0.);
                          }
                        })();
                        {
                          const $t29702 = (() => {
                            {
                              const $t29700 = (() => {
                                {
                                  const $t29698 = (dx * dx);
                                  {
                                    const $t29699 = (dy * dy);
                                    return ($t29698 + $t29699);
                                  }
                                }
                              })();
                              {
                                const $t29701 = (range * range);
                                return ($t29700 < $t29701);
                              }
                            }
                          })();
                          return ($t29697 && $t29702);
                        }
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
        const $t29707 = (() => {
          {
            const $t29706 = (() => {
              {
                const $t29705 = (t * 6.);
                return Math.sin($t29705);
              }
            })();
            return (0.5 * $t29706);
          }
        })();
        return (0.5 + $t29707);
      }
    })();
    (() => {
      {
        const $t29709 = (() => {
          {
            const $t29708 = (0.45 * pulse);
            return (0.3 + $t29708);
          }
        })();
        return Canvas$set_global_alpha(ctx, $t29709);
      }
    })();
    (() => {
      return Canvas$set_stroke_style(ctx, "#ffffff");
    })();
    (() => {
      {
        const $t29711 = (() => {
          {
            const $t29710 = (1.6 * pulse);
            return (1.2 + $t29710);
          }
        })();
        return Canvas$set_line_width(ctx, $t29711);
      }
    })();
    (() => {
      return Canvas$begin_path(ctx);
    })();
    (() => {
      {
        const $t29712 = s.x;
        {
          const $t29713 = s.y;
          {
            const $t29714 = s.capture_radius;
            return Canvas$arc(ctx, $t29712, $t29713, $t29714, 0., 6.28318530718);
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
      const $t29716 = s.orbits;
      return draw_orbit_rings(ctx, s, $t29716);
    }
  })();
  (() => {
    {
      const $t29717 = (() => {
        {
          const $t29606_i5481 = (() => {
            {
              const $t29604_i5479 = s.x;
              {
                const $t29605_i5480 = s.y;
                {
                  const x_i12293 = (() => {
                    {
                      const $t29500_i12292 = (() => {
                        {
                          const $t29499_i12291 = (() => {
                            {
                              const $t29497_i12289 = ($t29604_i5479 * 12.9898);
                              {
                                const $t29498_i12290 = ($t29605_i5480 * 78.233);
                                return ($t29497_i12289 + $t29498_i12290);
                              }
                            }
                          })();
                          return Math.sin($t29499_i12291);
                        }
                      })();
                      return ($t29500_i12292 * 43758.5453);
                    }
                  })();
                  {
                    const $t29501_i12295 = (() => {
                      {
                        const $t1603_i5323_i12294 = Math.floor(x_i12293);
                        return $t1603_i5323_i12294;
                      }
                    })();
                    return (x_i12293 - $t29501_i12295);
                  }
                }
              }
            }
          })();
          return ($t29606_i5481 < 0.8);
        }
      })();
      if ($t29717 === true) {
        return (() => {
          {
            const pulse = (() => {
              {
                const $t29723 = (() => {
                  {
                    const $t29722 = (() => {
                      {
                        const $t29721 = (() => {
                          {
                            const $t29719 = (() => {
                              {
                                const $t29718 = (() => {
                                  {
                                    const $t29618_i5477 = (() => {
                                      {
                                        const $t29617_i5476 = (() => {
                                          {
                                            const $t29614_i5473 = (() => {
                                              {
                                                const $t29613_i5472 = s.x;
                                                return ($t29613_i5472 + 2.);
                                              }
                                            })();
                                            {
                                              const $t29616_i5475 = (() => {
                                                {
                                                  const $t29615_i5474 = s.y;
                                                  return ($t29615_i5474 + 2.);
                                                }
                                              })();
                                              {
                                                const x_i12284 = (() => {
                                                  {
                                                    const $t29500_i12283 = (() => {
                                                      {
                                                        const $t29499_i12282 = (() => {
                                                          {
                                                            const $t29497_i12280 = ($t29614_i5473 * 12.9898);
                                                            {
                                                              const $t29498_i12281 = ($t29616_i5475 * 78.233);
                                                              return ($t29497_i12280 + $t29498_i12281);
                                                            }
                                                          }
                                                        })();
                                                        return Math.sin($t29499_i12282);
                                                      }
                                                    })();
                                                    return ($t29500_i12283 * 43758.5453);
                                                  }
                                                })();
                                                {
                                                  const $t29501_i12286 = (() => {
                                                    {
                                                      const $t1603_i5323_i12285 = Math.floor(x_i12284);
                                                      return $t1603_i5323_i12285;
                                                    }
                                                  })();
                                                  return (x_i12284 - $t29501_i12286);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        return ($t29617_i5476 * 1.8);
                                      }
                                    })();
                                    return (0.6 + $t29618_i5477);
                                  }
                                })();
                                return (t * $t29718);
                              }
                            })();
                            {
                              const $t29720 = (() => {
                                {
                                  const $t29623_i5469 = (() => {
                                    {
                                      const $t29620_i5466 = (() => {
                                        {
                                          const $t29619_i5465 = s.x;
                                          return ($t29619_i5465 + 3.);
                                        }
                                      })();
                                      {
                                        const $t29622_i5468 = (() => {
                                          {
                                            const $t29621_i5467 = s.y;
                                            return ($t29621_i5467 + 3.);
                                          }
                                        })();
                                        {
                                          const x_i12275 = (() => {
                                            {
                                              const $t29500_i12274 = (() => {
                                                {
                                                  const $t29499_i12273 = (() => {
                                                    {
                                                      const $t29497_i12271 = ($t29620_i5466 * 12.9898);
                                                      {
                                                        const $t29498_i12272 = ($t29622_i5468 * 78.233);
                                                        return ($t29497_i12271 + $t29498_i12272);
                                                      }
                                                    }
                                                  })();
                                                  return Math.sin($t29499_i12273);
                                                }
                                              })();
                                              return ($t29500_i12274 * 43758.5453);
                                            }
                                          })();
                                          {
                                            const $t29501_i12277 = (() => {
                                              {
                                                const $t1603_i5323_i12276 = Math.floor(x_i12275);
                                                return $t1603_i5323_i12276;
                                              }
                                            })();
                                            return (x_i12275 - $t29501_i12277);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return ($t29623_i5469 * 6.28318530718);
                                }
                              })();
                              return ($t29719 + $t29720);
                            }
                          }
                        })();
                        return Math.sin($t29721);
                      }
                    })();
                    return (0.5 * $t29722);
                  }
                })();
                return (0.5 + $t29723);
              }
            })();
            {
              const $t29724 = (() => {
                {
                  const r_i5460 = (() => {
                    {
                      const $t29608_i5457 = (() => {
                        {
                          const $t29607_i5456 = s.x;
                          return ($t29607_i5456 + 1.);
                        }
                      })();
                      {
                        const $t29610_i5459 = (() => {
                          {
                            const $t29609_i5458 = s.y;
                            return ($t29609_i5458 + 1.);
                          }
                        })();
                        {
                          const x_i12266 = (() => {
                            {
                              const $t29500_i12265 = (() => {
                                {
                                  const $t29499_i12264 = (() => {
                                    {
                                      const $t29497_i12262 = ($t29608_i5457 * 12.9898);
                                      {
                                        const $t29498_i12263 = ($t29610_i5459 * 78.233);
                                        return ($t29497_i12262 + $t29498_i12263);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29499_i12264);
                                }
                              })();
                              return ($t29500_i12265 * 43758.5453);
                            }
                          })();
                          {
                            const $t29501_i12268 = (() => {
                              {
                                const $t1603_i5323_i12267 = Math.floor(x_i12266);
                                return $t1603_i5323_i12267;
                              }
                            })();
                            return (x_i12266 - $t29501_i12268);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t29611_i5461 = (r_i5460 < 0.34);
                    if ($t29611_i5461 === true) {
                      return 0;
                    } else {
                      return (() => {
                        {
                          const $t29612_i5462 = (r_i5460 < 0.67);
                          if ($t29612_i5462 === true) {
                            return 1;
                          } else {
                            return 2;
                          }
                        }
                      })();
                    }
                  }
                }
              })();
              if ($t29724 === 0) {
                return (() => {
                  {
                    const $jp_clo29727 = (() => {
                      return { $: "$Clo_$jp29726$3827", _0: $jp29726$apply$3827, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_ring(ctx, s, pulse);
                  }
                })();
              } else if ($t29724 === 1) {
                return (() => {
                  {
                    const $jp_clo29729 = (() => {
                      return { $: "$Clo_$jp29728$3828", _0: $jp29728$apply$3828, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_halo(ctx, s, pulse);
                  }
                })();
              } else {
                return (() => {
                  {
                    const $t29725 = (() => {
                      {
                        const $t29631_i5454 = (() => {
                          {
                            const $t29630_i5453 = (() => {
                              {
                                const $t29629_i5452 = (() => {
                                  {
                                    const $t29626_i5449 = (() => {
                                      {
                                        const $t29625_i5448 = s.x;
                                        return ($t29625_i5448 + 4.);
                                      }
                                    })();
                                    {
                                      const $t29628_i5451 = (() => {
                                        {
                                          const $t29627_i5450 = s.y;
                                          return ($t29627_i5450 + 4.);
                                        }
                                      })();
                                      {
                                        const x_i12257 = (() => {
                                          {
                                            const $t29500_i12256 = (() => {
                                              {
                                                const $t29499_i12255 = (() => {
                                                  {
                                                    const $t29497_i12253 = ($t29626_i5449 * 12.9898);
                                                    {
                                                      const $t29498_i12254 = ($t29628_i5451 * 78.233);
                                                      return ($t29497_i12253 + $t29498_i12254);
                                                    }
                                                  }
                                                })();
                                                return Math.sin($t29499_i12255);
                                              }
                                            })();
                                            return ($t29500_i12256 * 43758.5453);
                                          }
                                        })();
                                        {
                                          const $t29501_i12259 = (() => {
                                            {
                                              const $t1603_i5323_i12258 = Math.floor(x_i12257);
                                              return $t1603_i5323_i12258;
                                            }
                                          })();
                                          return (x_i12257 - $t29501_i12259);
                                        }
                                      }
                                    }
                                  }
                                })();
                                return ($t29629_i5452 * 4.);
                              }
                            })();
                            return Math.trunc($t29630_i5453);
                          }
                        })();
                        return (2 + $t29631_i5454);
                      }
                    })();
                    return draw_pulse_particle(ctx, s, t, $t29725, 0);
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
      const $t29730 = star_targeted(s, aim);
      if ($t29730 === true) {
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
      const $t29731 = s.x;
      {
        const $t29732 = s.y;
        {
          const $t29733 = s.radius;
          return Canvas$arc(ctx, $t29731, $t29732, $t29733, 0., 6.28318530718);
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
            const $t29741 = (() => {
              {
                const $t29740 = (seed * 37.719);
                return (fx + $t29740);
              }
            })();
            {
              const $t29743 = (() => {
                {
                  const $t29742 = (seed * 12.9898);
                  return (fy - $t29742);
                }
              })();
              {
                const x_i5507 = (() => {
                  {
                    const $t29738_i5506 = (() => {
                      {
                        const $t29737_i5505 = (() => {
                          {
                            const $t29735_i5503 = ($t29741 * 12.9898);
                            {
                              const $t29736_i5504 = ($t29743 * 78.233);
                              return ($t29735_i5503 + $t29736_i5504);
                            }
                          }
                        })();
                        return Math.sin($t29737_i5505);
                      }
                    })();
                    return ($t29738_i5506 * 43758.5453);
                  }
                })();
                {
                  const $t29739_i5508 = (() => {
                    {
                      const $t1603_i12303 = Math.floor(x_i5507);
                      return $t1603_i12303;
                    }
                  })();
                  return (x_i5507 - $t29739_i5508);
                }
              }
            }
          }
        })();
        {
          const h2 = (() => {
            {
              const $t29746 = (() => {
                {
                  const $t29744 = (fy * 3.271);
                  {
                    const $t29745 = (seed * 71.238);
                    return ($t29744 - $t29745);
                  }
                }
              })();
              {
                const $t29749 = (() => {
                  {
                    const $t29747 = (fx * 1.373);
                    {
                      const $t29748 = (seed * 5.113);
                      return ($t29747 + $t29748);
                    }
                  }
                })();
                {
                  const x_i5499 = (() => {
                    {
                      const $t29738_i5498 = (() => {
                        {
                          const $t29737_i5497 = (() => {
                            {
                              const $t29735_i5495 = ($t29746 * 12.9898);
                              {
                                const $t29736_i5496 = ($t29749 * 78.233);
                                return ($t29735_i5495 + $t29736_i5496);
                              }
                            }
                          })();
                          return Math.sin($t29737_i5497);
                        }
                      })();
                      return ($t29738_i5498 * 43758.5453);
                    }
                  })();
                  {
                    const $t29739_i5500 = (() => {
                      {
                        const $t1603_i12300 = Math.floor(x_i5499);
                        return $t1603_i12300;
                      }
                    })();
                    return (x_i5499 - $t29739_i5500);
                  }
                }
              }
            }
          })();
          {
            const $t29752 = (() => {
              {
                const $t29750 = (h1 * 269.5);
                {
                  const $t29751 = (h2 * 183.3);
                  return ($t29750 + $t29751);
                }
              }
            })();
            {
              const $t29756 = (() => {
                {
                  const $t29755 = (() => {
                    {
                      const $t29753 = (fx * 0.618);
                      {
                        const $t29754 = (fy * 0.573);
                        return ($t29753 + $t29754);
                      }
                    }
                  })();
                  return ($t29755 + seed);
                }
              })();
              {
                const x_i5491 = (() => {
                  {
                    const $t29738_i5490 = (() => {
                      {
                        const $t29737_i5489 = (() => {
                          {
                            const $t29735_i5487 = ($t29752 * 12.9898);
                            {
                              const $t29736_i5488 = ($t29756 * 78.233);
                              return ($t29735_i5487 + $t29736_i5488);
                            }
                          }
                        })();
                        return Math.sin($t29737_i5489);
                      }
                    })();
                    return ($t29738_i5490 * 43758.5453);
                  }
                })();
                {
                  const $t29739_i5492 = (() => {
                    {
                      const $t1603_i12297 = Math.floor(x_i5491);
                      return $t1603_i12297;
                    }
                  })();
                  return (x_i5491 - $t29739_i5492);
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
      const $t29758 = (h > 0.5);
      if ($t29758 === true) {
        return {  };
      } else {
        return (() => {
          {
            const jx = (() => {
              {
                const $t29759 = (gy + 1000);
                return bg_hash(gx, $t29759, seed);
              }
            })();
            {
              const jy = (() => {
                {
                  const $t29760 = (gx + 1000);
                  return bg_hash($t29760, gy, seed);
                }
              })();
              {
                const x = (() => {
                  {
                    const $t29762 = (() => {
                      {
                        const $t29761 = gx;
                        return ($t29761 * cell);
                      }
                    })();
                    {
                      const $t29763 = (jx * cell);
                      return ($t29762 + $t29763);
                    }
                  }
                })();
                {
                  const y = (() => {
                    {
                      const $t29765 = (() => {
                        {
                          const $t29764 = gy;
                          return ($t29764 * cell);
                        }
                      })();
                      {
                        const $t29766 = (jy * cell);
                        return ($t29765 + $t29766);
                      }
                    }
                  })();
                  {
                    const br = (() => {
                      {
                        const $t29770 = (() => {
                          {
                            const $t29769 = (() => {
                              {
                                const $t29767 = (gx + 2000);
                                {
                                  const $t29768 = (gy + 2000);
                                  return bg_hash($t29767, $t29768, seed);
                                }
                              }
                            })();
                            return (0.45 * $t29769);
                          }
                        })();
                        return (0.12 + $t29770);
                      }
                    })();
                    {
                      const st = (() => {
                        {
                          const $t29771 = (gx - 2000);
                          {
                            const $t29772 = (gy - 2000);
                            return bg_hash($t29771, $t29772, seed);
                          }
                        }
                      })();
                      {
                        const sz = (() => {
                          {
                            const $t29774 = (() => {
                              {
                                const $t29773 = (1.8 * st);
                                return ($t29773 * st);
                              }
                            })();
                            return (1. + $t29774);
                          }
                        })();
                        {
                          const is_pulsing = (() => {
                            {
                              const $t29777 = (() => {
                                {
                                  const $t29775 = (gx + 3000);
                                  {
                                    const $t29776 = (gy + 3000);
                                    return bg_hash($t29775, $t29776, seed);
                                  }
                                }
                              })();
                              return ($t29777 < 0.04);
                            }
                          })();
                          {
                            let pulse;
                            if (is_pulsing === true) {
                              pulse = (() => {
                                {
                                  const speed = (() => {
                                    {
                                      const $t29781 = (() => {
                                        {
                                          const $t29780 = (() => {
                                            {
                                              const $t29779 = (gx + 4000);
                                              return bg_hash($t29779, gy, seed);
                                            }
                                          })();
                                          return (0.45 * $t29780);
                                        }
                                      })();
                                      return (0.35 + $t29781);
                                    }
                                  })();
                                  {
                                    const phase = (() => {
                                      {
                                        const $t29783 = (() => {
                                          {
                                            const $t29782 = (gy + 4000);
                                            return bg_hash(gx, $t29782, seed);
                                          }
                                        })();
                                        return ($t29783 * 6.28318530718);
                                      }
                                    })();
                                    {
                                      const $t29788 = (() => {
                                        {
                                          const $t29787 = (() => {
                                            {
                                              const $t29786 = (() => {
                                                {
                                                  const $t29785 = (t * speed);
                                                  return ($t29785 + phase);
                                                }
                                              })();
                                              return Math.sin($t29786);
                                            }
                                          })();
                                          return (0.5 * $t29787);
                                        }
                                      })();
                                      return (0.5 + $t29788);
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
                                    const $t29791 = (() => {
                                      {
                                        const $t29790 = (() => {
                                          {
                                            const $t29789 = (1. - br);
                                            return ($t29789 * 0.6);
                                          }
                                        })();
                                        return ($t29790 * pulse);
                                      }
                                    })();
                                    return (br + $t29791);
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
                                      const $t29793 = (() => {
                                        {
                                          const $t29792 = (0.35 * pulse);
                                          return (1. + $t29792);
                                        }
                                      })();
                                      return (sz * $t29793);
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
    const $t29795 = (gx > gx_max);
    if ($t29795 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_cell(ctx, gx, gy, cell, seed, t);
        })();
        {
          const $t29796 = (gx + 1);
          return draw_bg_row(ctx, $t29796, gx_max, gy, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_row$clo = { _0: ($_, ctx, gx, gx_max, gy, cell, seed, t) => draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) };

function draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) {
  {
    const $t29797 = (gy > gy_max);
    if ($t29797 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_row(ctx, gx0, gx1, gy, cell, seed, t);
        })();
        {
          const $t29798 = (gy + 1);
          return draw_bg_rows(ctx, gx0, gx1, $t29798, gy_max, cell, seed, t);
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
        const $t29801 = (() => {
          {
            const $t29800 = (() => {
              {
                const $t29799 = (cam_x / 70.);
                {
                  const $t1603_i5517 = Math.floor($t29799);
                  return $t1603_i5517;
                }
              }
            })();
            return Math.trunc($t29800);
          }
        })();
        return ($t29801 - 1);
      }
    })();
    {
      const gx1 = (() => {
        {
          const $t29805 = (() => {
            {
              const $t29804 = (() => {
                {
                  const $t29803 = (() => {
                    {
                      const $t29802 = (cam_x + view_w);
                      return ($t29802 / 70.);
                    }
                  })();
                  {
                    const $t1603_i5515 = Math.floor($t29803);
                    return $t1603_i5515;
                  }
                }
              })();
              return Math.trunc($t29804);
            }
          })();
          return ($t29805 + 1);
        }
      })();
      {
        const gy0 = (() => {
          {
            const $t29808 = (() => {
              {
                const $t29807 = (() => {
                  {
                    const $t29806 = (cam / 70.);
                    {
                      const $t1603_i5513 = Math.floor($t29806);
                      return $t1603_i5513;
                    }
                  }
                })();
                return Math.trunc($t29807);
              }
            })();
            return ($t29808 - 1);
          }
        })();
        {
          const gy1 = (() => {
            {
              const $t29812 = (() => {
                {
                  const $t29811 = (() => {
                    {
                      const $t29810 = (() => {
                        {
                          const $t29809 = (cam + view_h);
                          return ($t29809 / 70.);
                        }
                      })();
                      {
                        const $t1603_i5511 = Math.floor($t29810);
                        return $t1603_i5511;
                      }
                    }
                  })();
                  return Math.trunc($t29811);
                }
              })();
              return ($t29812 + 1);
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
      const $f29819 = clouds._0;
      const $f29820 = clouds._1;
      {
        const rest = (() => {
          return $f29820;
        })();
        {
          const c = (() => {
            return $f29819;
          })();
          (() => {
            {
              const $t29813 = c.x;
              {
                const $t29814 = c.y;
                {
                  const $t29815 = c.radius;
                  {
                    const $t29818 = (() => {
                      {
                        const $t29817 = c.strength;
                        return (0.16 * $t29817);
                      }
                    })();
                    return Canvas$fill_noise_circle(ctx, $t29813, $t29814, $t29815, $t29818);
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
    const $t29825 = (() => {
      {
        const margin_i5525 = (700. + 90.);
        {
          const $t29429_i5526 = { $: "Nil" };
          {
            const $t29430_i5527 = Perihelion$Nebula$filter_visible(stars, cam, view_h, margin_i5525, $t29429_i5526);
            {
              const $t29431_i5528 = { $: "Nil" };
              return Perihelion$Nebula$collect_star_clouds($t29430_i5527, seed, $t29431_i5528);
            }
          }
        }
      }
    })();
    {
      const $rc_629 = draw_nebula_clouds(ctx, $t29825);
      return $rc_629;
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
      const $f29834 = stars._0;
      const $f29835 = stars._1;
      {
        const rest = $f29835;
        {
          const s = $f29834;
          (() => {
            {
              const $t29833 = (() => {
                {
                  const $t29829 = (() => {
                    {
                      const $t29826 = s.y;
                      {
                        const $t29828 = (() => {
                          {
                            const $t29827 = (cam + view_h);
                            return ($t29827 + 100.);
                          }
                        })();
                        return ($t29826 < $t29828);
                      }
                    }
                  })();
                  {
                    const $t29832 = (() => {
                      {
                        const $t29830 = s.y;
                        {
                          const $t29831 = (cam - 100.);
                          return ($t29830 > $t29831);
                        }
                      }
                    })();
                    return ($t29829 && $t29832);
                  }
                }
              })();
              if ($t29833 === true) {
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
        const $t29846 = i;
        {
          const $t29848 = (6.28318530718 / 8.);
          return ($t29846 * $t29848);
        }
      }
    })();
    {
      const jitter = (() => {
        {
          const $t29851 = (() => {
            {
              const $t29850 = (() => {
                {
                  const $t29849 = a.shape_seed;
                  {
                    const x_i5542 = (() => {
                      {
                        const $t29844_i5541 = (() => {
                          {
                            const $t29843_i5540 = (() => {
                              {
                                const $t29840_i5537 = ($t29849 * 12.9898);
                                {
                                  const $t29842_i5539 = (() => {
                                    {
                                      const $t29841_i5538 = i;
                                      return ($t29841_i5538 * 78.233);
                                    }
                                  })();
                                  return ($t29840_i5537 + $t29842_i5539);
                                }
                              }
                            })();
                            return Math.sin($t29843_i5540);
                          }
                        })();
                        return ($t29844_i5541 * 43758.5453);
                      }
                    })();
                    {
                      const $t29845_i5543 = (() => {
                        {
                          const $t1603_i12306 = Math.floor(x_i5542);
                          return $t1603_i12306;
                        }
                      })();
                      return (x_i5542 - $t29845_i5543);
                    }
                  }
                }
              })();
              return (0.6 * $t29850);
            }
          })();
          return (0.7 + $t29851);
        }
      })();
      {
        const r = (() => {
          {
            const $t29852 = a.radius;
            return ($t29852 * jitter);
          }
        })();
        {
          const pt = (() => {
            {
              const $t29856 = (() => {
                {
                  const $t29853 = a.x;
                  {
                    const $t29855 = (() => {
                      {
                        const $t29854 = Math.cos(angle);
                        return ($t29854 * r);
                      }
                    })();
                    return ($t29853 + $t29855);
                  }
                }
              })();
              {
                const $t29860 = (() => {
                  {
                    const $t29857 = a.y;
                    {
                      const $t29859 = (() => {
                        {
                          const $t29858 = Math.sin(angle);
                          return ($t29858 * r);
                        }
                      })();
                      return ($t29857 + $t29859);
                    }
                  }
                })();
                return { _0: $t29856, _1: $t29860 };
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
    const $t29861 = (i > 7);
    if ($t29861 === true) {
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
                      const $jp_clo29863 = (() => {
                        return { $: "$Clo_$jp29862$3831", _0: $jp29862$apply$3831, _1: ctx, _2: px, _3: py };
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
                const $t29864 = (i + 1);
                return draw_asteroid_edges(ctx, a, $t29864);
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
      const $f29873 = asteroids._0;
      const $f29874 = asteroids._1;
      {
        const rest = (() => {
          return $f29874;
        })();
        {
          const a = (() => {
            return $f29873;
          })();
          {
            const color = (() => {
              {
                const $t29866 = a.mode;
                switch ($t29866.$) {
                  case "AsteroidDrifting": {
                    return "#8a8a94";
                    break;
                  }
                  case "AsteroidOrbiting": {
                    const $f29867 = $t29866._0;
                    const $f29868 = $t29866._1;
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
      const $f29882 = shots._0;
      const $f29883 = shots._1;
      {
        const rest = (() => {
          return $f29883;
        })();
        {
          const s = (() => {
            return $f29882;
          })();
          (() => {
            return Canvas$set_fill_style(ctx, color);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29879 = s.x;
              {
                const $t29880 = s.y;
                return Canvas$arc(ctx, $t29879, $t29880, r, 0., 6.28318530718);
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
    const $t29888 = sh.mode;
    switch ($t29888.$) {
      case "ShipOrbiting": {
        const $f29892 = $t29888._0;
        {
          const angle = (() => {
            return $f29892;
          })();
          {
            const d = (0. - 1.);
            {
              const $t29891 = (d * 1.5707963);
              return (angle + $t29891);
            }
          }
        }
        break;
      }
      case "ShipFlying": {
        const $f29893 = $t29888._0;
        const $f29894 = $t29888._1;
        {
          const vy = (() => {
            return $f29894;
          })();
          {
            const vx = (() => {
              return $f29893;
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
      const $f29903 = ships._0;
      const $f29904 = ships._1;
      {
        const rest = (() => {
          return $f29904;
        })();
        {
          const sh = (() => {
            return $f29903;
          })();
          {
            const pos = (() => {
              {
                const pos_i5555 = (() => {
                  {
                    const $t27623_i5553 = sh.x;
                    {
                      const $t27624_i5554 = sh.y;
                      return { _0: $t27623_i5553, _1: $t27624_i5554 };
                    }
                  }
                })();
                return pos_i5555;
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
                      const $t29899 = (0. - 6.);
                      return Canvas$line_to(ctx, $t29899, 5.);
                    }
                  })();
                  (() => {
                    {
                      const $t29900 = (0. - 6.);
                      {
                        const $t29901 = (0. - 5.);
                        return Canvas$line_to(ctx, $t29900, $t29901);
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
      const $f29912 = pickups._0;
      const $f29913 = pickups._1;
      {
        const rest = (() => {
          return $f29913;
        })();
        {
          const pk = (() => {
            return $f29912;
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
              const $t29909 = pk.x;
              {
                const $t29910 = pk.y;
                return Canvas$arc(ctx, $t29909, $t29910, 8., 0., 6.28318530718);
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
    const $t29918 = (i >= 5);
    if ($t29918 === true) {
      return {  };
    } else {
      return (() => {
        switch (runs.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f29931 = runs._0;
            const $f29932 = runs._1;
            {
              const rest = (() => {
                return $f29932;
              })();
              {
                const r = (() => {
                  return $f29931;
                })();
                (() => {
                  return Canvas$set_font(ctx, "14px sans-serif");
                })();
                (() => {
                  {
                    const $t29927 = (() => {
                      {
                        const $t29926 = (() => {
                          {
                            const $t29923 = (() => {
                              {
                                const $t29920 = (() => {
                                  {
                                    const $t29919 = r.score;
                                    return String($t29919);
                                  }
                                })();
                                {
                                  const $t29922 = (() => {
                                    {
                                      const $t29921 = r.max_mult;
                                      return String($t29921);
                                    }
                                  })();
                                  {
                                    const $rc_632 = march_string_concat3($t29920, " x", $t29922);
                                    return $rc_632;
                                  }
                                }
                              }
                            })();
                            {
                              const $t29925 = (() => {
                                {
                                  const $t29924 = r.stars;
                                  return String($t29924);
                                }
                              })();
                              {
                                const $rc_631 = march_string_concat3($t29923, " · ", $t29925);
                                return $rc_631;
                              }
                            }
                          }
                        })();
                        {
                          const $rc_630 = ($t29926 + " stars");
                          return $rc_630;
                        }
                      }
                    })();
                    {
                      const $t29928 = (view_w / 2.);
                      return Canvas$fill_text(ctx, $t29927, $t29928, y);
                    }
                  }
                })();
                {
                  const $t29929 = (y + 20.);
                  {
                    const $t29930 = (i + 1);
                    return draw_runs(ctx, rest, view_w, $t29929, $t29930);
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
      const $t29937 = game.ball_x;
      {
        const $t29938 = game.ball_y;
        return Canvas$arc(ctx, $t29937, $t29938, 6., 0., 6.28318530718);
      }
    }
  })();
  (() => {
    return Canvas$fill(ctx);
  })();
  {
    const $t29941 = (() => {
      {
        const $t29940 = game.shield;
        return ($t29940 > 0);
      }
    })();
    if ($t29941 === true) {
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
            const $t29942 = game.ball_x;
            {
              const $t29943 = game.ball_y;
              return Canvas$arc(ctx, $t29942, $t29943, 10., 0., 6.28318530718);
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
      const $t29947 = (cx - 60.);
      {
        const $t29949 = (() => {
          {
            const $t29948 = (view_h / 2.);
            return ($t29948 - 60.);
          }
        })();
        return Canvas$stroke_rect(ctx, $t29947, $t29949, 120., 120.);
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
    let $t29950;
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29945_i5562 = u._0;
        $t29950 = (() => {
          switch ($f29945_i5562.$) {
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
        $t29950 = "Faster Fire";
        break;
      }
      case "DefenseBulletWard": {
        $t29950 = "Bullet Ward";
        break;
      }
      case "DefenseDeflector": {
        $t29950 = "Deflector Plating";
        break;
      }
      case "DefenseShield": {
        $t29950 = "Reinforced Shield";
        break;
      }
      case "SpecialItem": {
        const $f29946_i5563 = u._0;
        $t29950 = (() => {
          switch ($f29946_i5563.$) {
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
        $t29950 = (() => { throw new Error("non-exhaustive pattern match"); })();
        break;
      }
    }
    {
      const $t29951 = (view_h / 2.);
      return Canvas$fill_text(ctx, $t29950, cx, $t29951);
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
      const $f29956 = choices._0;
      const $f29957 = choices._1;
      {
        const rest = (() => {
          return $f29957;
        })();
        {
          const u = (() => {
            return $f29956;
          })();
          {
            const col_w = (view_w / 3.);
            (() => {
              {
                const $t29954 = (() => {
                  {
                    const $t29953 = (() => {
                      {
                        const $t29952 = i;
                        return ($t29952 + 0.5);
                      }
                    })();
                    return (col_w * $t29953);
                  }
                })();
                {
                  const $rc_633 = (() => {
                    return draw_milestone_card(ctx, u, $t29954, view_h);
                  })();
                  return $rc_633;
                }
              }
            })();
            {
              const $t29955 = (i + 1);
              return draw_milestone_cards(ctx, rest, view_w, view_h, $t29955);
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
      const $t29963 = (() => {
        {
          const $t29962 = game.score;
          return String($t29962);
        }
      })();
      return Canvas$fill_text(ctx, $t29963, 14., 28.);
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "right");
  })();
  (() => {
    {
      const $t29966 = (() => {
        {
          const $t29965 = (() => {
            {
              const $t29964 = game.best;
              return String($t29964);
            }
          })();
          {
            const $rc_641 = ("best " + $t29965);
            return $rc_641;
          }
        }
      })();
      {
        const $t29968 = (() => {
          {
            const $t29967 = game.view_w;
            return ($t29967 - 14.);
          }
        })();
        return Canvas$fill_text(ctx, $t29966, $t29968, 28.);
      }
    }
  })();
  (() => {
    {
      const $t29970 = (() => {
        {
          const $t29969 = game.multiplier;
          return ($t29969 > 1);
        }
      })();
      if ($t29970 === true) {
        return (() => {
          (() => {
            return Canvas$set_text_align(ctx, "left");
          })();
          {
            const $t29973 = (() => {
              {
                const $t29972 = (() => {
                  {
                    const $t29971 = game.multiplier;
                    return String($t29971);
                  }
                })();
                {
                  const $rc_640 = ("x" + $t29972);
                  return $rc_640;
                }
              }
            })();
            return Canvas$fill_text(ctx, $t29973, 14., 52.);
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
      const $t29976 = (() => {
        {
          const $t29975 = (() => {
            {
              const $t29974 = Perihelion$Core$active_weapon(game);
              return { $: "OffenseWeapon", _0: $t29974 };
            }
          })();
          {
            let $rc_639;
            switch ($t29975.$) {
              case "OffenseWeapon": {
                const $f29945_i5571 = $t29975._0;
                $rc_639 = (() => {
                  switch ($f29945_i5571.$) {
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
                $rc_639 = "Faster Fire";
                break;
              }
              case "DefenseBulletWard": {
                $rc_639 = "Bullet Ward";
                break;
              }
              case "DefenseDeflector": {
                $rc_639 = "Deflector Plating";
                break;
              }
              case "DefenseShield": {
                $rc_639 = "Reinforced Shield";
                break;
              }
              case "SpecialItem": {
                const $f29946_i5572 = $t29975._0;
                $rc_639 = (() => {
                  switch ($f29946_i5572.$) {
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
                $rc_639 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            return $rc_639;
          }
        }
      })();
      {
        const $t29978 = (() => {
          {
            const $t29977 = game.view_h;
            return ($t29977 - 60.);
          }
        })();
        return Canvas$fill_text(ctx, $t29976, 14., $t29978);
      }
    }
  })();
  (() => {
    {
      const $t29979 = game.special;
      switch ($t29979.$) {
        case "None": {
          return {  };
          break;
        }
        case "Some": {
          const $f29987 = $t29979._0;
          {
            const k = (() => {
              return $f29987;
            })();
            {
              const $t29984 = (() => {
                {
                  const $t29981 = (() => {
                    {
                      const $t29980 = { $: "SpecialItem", _0: k };
                      {
                        let $rc_638;
                        switch ($t29980.$) {
                          case "OffenseWeapon": {
                            const $f29945_i5568 = $t29980._0;
                            $rc_638 = (() => {
                              switch ($f29945_i5568.$) {
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
                            $rc_638 = "Faster Fire";
                            break;
                          }
                          case "DefenseBulletWard": {
                            $rc_638 = "Bullet Ward";
                            break;
                          }
                          case "DefenseDeflector": {
                            $rc_638 = "Deflector Plating";
                            break;
                          }
                          case "DefenseShield": {
                            $rc_638 = "Reinforced Shield";
                            break;
                          }
                          case "SpecialItem": {
                            const $f29946_i5569 = $t29980._0;
                            $rc_638 = (() => {
                              switch ($f29946_i5569.$) {
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
                            $rc_638 = (() => { throw new Error("non-exhaustive pattern match"); })();
                            break;
                          }
                        }
                        return $rc_638;
                      }
                    }
                  })();
                  {
                    const $t29983 = (() => {
                      {
                        const $t29982 = game.special_charges;
                        return String($t29982);
                      }
                    })();
                    {
                      const $rc_637 = march_string_concat3($t29981, " x", $t29983);
                      return $rc_637;
                    }
                  }
                }
              })();
              {
                const $t29986 = (() => {
                  {
                    const $t29985 = game.view_h;
                    return ($t29985 - 40.);
                  }
                })();
                return Canvas$fill_text(ctx, $t29984, 14., $t29986);
              }
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
        const $t29989 = (() => {
          {
            const $t29988 = game.bullet_ward;
            if ($t29988 === true) {
              return "ward ";
            } else {
              return "";
            }
          }
        })();
        {
          const $t29991 = (() => {
            {
              const $t29990 = game.deflector_plating;
              if ($t29990 === true) {
                return "deflect ";
              } else {
                return "";
              }
            }
          })();
          {
            const $t29996 = (() => {
              {
                const $t29993 = (() => {
                  {
                    const $t29992 = game.shield;
                    return ($t29992 > 0);
                  }
                })();
                if ($t29993 === true) {
                  return (() => {
                    {
                      const $t29995 = (() => {
                        {
                          const $t29994 = game.shield;
                          return String($t29994);
                        }
                      })();
                      {
                        const $rc_636 = ("shield x" + $t29995);
                        return $rc_636;
                      }
                    }
                  })();
                } else {
                  return "";
                }
              }
            })();
            {
              const $rc_635 = march_string_concat3($t29989, $t29991, $t29996);
              return $rc_635;
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t29998 = (() => {
          {
            const $t29997 = game.view_h;
            return ($t29997 - 20.);
          }
        })();
        return Canvas$fill_text(ctx, defense_tags, 14., $t29998);
      }
    })();
    (() => {
      return Canvas$set_text_align(ctx, "center");
    })();
    {
      const $t29999 = game.phase;
      switch ($t29999.$) {
        case "Ready": {
          (() => {
            return Canvas$set_font(ctx, "22px sans-serif");
          })();
          {
            const $t30001 = (() => {
              {
                const $t30000 = game.view_w;
                return ($t30000 / 2.);
              }
            })();
            {
              const $t30003 = (() => {
                {
                  const $t30002 = game.view_h;
                  return ($t30002 / 2.);
                }
              })();
              return Canvas$fill_text(ctx, "tap to start", $t30001, $t30003);
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
              const $t30006 = (() => {
                {
                  const $t30005 = (() => {
                    {
                      const $t30004 = game.score;
                      return String($t30004);
                    }
                  })();
                  {
                    const $rc_634 = march_string_concat3("score ", $t30005, " — tap to retry");
                    return $rc_634;
                  }
                }
              })();
              {
                const $t30008 = (() => {
                  {
                    const $t30007 = game.view_w;
                    return ($t30007 / 2.);
                  }
                })();
                {
                  const $t30010 = (() => {
                    {
                      const $t30009 = game.view_h;
                      return ($t30009 / 2.);
                    }
                  })();
                  return Canvas$fill_text(ctx, $t30006, $t30008, $t30010);
                }
              }
            }
          })();
          {
            const $t30011 = game.runs;
            {
              const $t30012 = game.view_w;
              {
                const $t30015 = (() => {
                  {
                    const $t30014 = (() => {
                      {
                        const $t30013 = game.view_h;
                        return ($t30013 / 2.);
                      }
                    })();
                    return ($t30014 + 36.);
                  }
                })();
                return draw_runs(ctx, $t30011, $t30012, $t30015, 0);
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
              const $t30017 = (() => {
                {
                  const $t30016 = game.view_w;
                  return ($t30016 / 2.);
                }
              })();
              {
                const $t30020 = (() => {
                  {
                    const $t30019 = (() => {
                      {
                        const $t30018 = game.view_h;
                        return ($t30018 / 2.);
                      }
                    })();
                    return ($t30019 - 90.);
                  }
                })();
                return Canvas$fill_text(ctx, "Choose an upgrade", $t30017, $t30020);
              }
            }
          })();
          {
            const $t30021 = game.milestone_choices;
            {
              const $t30022 = game.view_w;
              {
                const $t30023 = game.view_h;
                return draw_milestone_cards(ctx, $t30021, $t30022, $t30023, 0);
              }
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
      const $t30024 = game.view_w;
      {
        const $t30025 = game.view_h;
        return Canvas$fill_rect(ctx, 0., 0., $t30024, $t30025);
      }
    }
  })();
  (() => {
    return Canvas$save(ctx);
  })();
  (() => {
    {
      const $t30027 = (() => {
        {
          const $t30026 = game.camera_x;
          return (0. - $t30026);
        }
      })();
      {
        const $t30029 = (() => {
          {
            const $t30028 = game.camera_y;
            return (0. - $t30028);
          }
        })();
        return Canvas$translate(ctx, $t30027, $t30029);
      }
    }
  })();
  {
    const seedf = (() => {
      {
        const $t30030 = game.seed;
        return $t30030;
      }
    })();
    (() => {
      {
        const $t30031 = game.camera_x;
        {
          const $t30032 = game.camera_y;
          {
            const $t30033 = game.view_w;
            {
              const $t30034 = game.view_h;
              {
                const $t30035 = fx.t;
                return draw_starfield(ctx, $t30031, $t30032, $t30033, $t30034, seedf, $t30035);
              }
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t30036 = game.stars;
        {
          const $t30037 = game.camera_y;
          {
            const $t30038 = game.view_h;
            return draw_nebula(ctx, $t30036, $t30037, $t30038, seedf);
          }
        }
      }
    })();
    {
      const aim = (() => {
        {
          const $t30039 = game.mode;
          switch ($t30039.$) {
            case "Flying": {
              const $f30043 = $t30039._0;
              const $f30044 = $t30039._1;
              {
                const vy = (() => {
                  return $f30044;
                })();
                {
                  const vx = (() => {
                    return $f30043;
                  })();
                  {
                    const $t30040 = game.ball_x;
                    {
                      const $t30041 = game.ball_y;
                      {
                        const $t30042 = { _0: $t30040, _1: $t30041, _2: vx, _3: vy };
                        return { $: "Some", _0: $t30042 };
                      }
                    }
                  }
                }
              }
              break;
            }
            case "Orbiting": {
              const $f30049 = $t30039._0;
              const $f30050 = $t30039._1;
              const $f30051 = $t30039._2;
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
          const $t30060 = game.stars;
          {
            const $t30061 = game.camera_y;
            {
              const $t30062 = game.view_h;
              {
                const $t30063 = fx.t;
                {
                  const $rc_643 = (() => {
                    return draw_stars(ctx, $t30060, $t30061, $t30062, $t30063, aim);
                  })();
                  return $rc_643;
                }
              }
            }
          }
        }
      })();
      (() => {
        {
          const $t30064 = Perihelion$Core$active_weapon(game);
          switch ($t30064.$) {
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
          const $t30067 = game.mode;
          switch ($t30067.$) {
            case "Orbiting": {
              const $f30075 = $t30067._0;
              const $f30076 = $t30067._1;
              const $f30077 = $t30067._2;
              {
                const angle = (() => {
                  return $f30077;
                })();
                {
                  const ring = (() => {
                    return $f30076;
                  })();
                  {
                    const idx = (() => {
                      return $f30075;
                    })();
                    {
                      const $t30068 = game.special;
                      switch ($t30068.$) {
                        case "Some": {
                          const $f30070 = $t30068._0;
                          switch ($f30070.$) {
                            case "TrajectoryPreview": {
                              {
                                const $t30069 = Perihelion$Core$predict_trajectory(game, idx, ring, angle);
                                {
                                  const $rc_642 = (() => {
                                    return draw_trajectory_preview(ctx, $t30069);
                                  })();
                                  return $rc_642;
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
              const $f30086 = $t30067._0;
              const $f30087 = $t30067._1;
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
          const $t30092 = fx.flash;
          return draw_flash(ctx, $t30092);
        }
      })();
      (() => {
        {
          const $t30093 = game.asteroids;
          return draw_asteroids(ctx, $t30093);
        }
      })();
      (() => {
        {
          const $t30094 = game.ships;
          return draw_ships(ctx, $t30094);
        }
      })();
      (() => {
        {
          const $t30095 = game.player_shots;
          return draw_shots(ctx, $t30095, "#ffffff", 3.);
        }
      })();
      (() => {
        {
          const $t30096 = game.enemy_shots;
          return draw_shots(ctx, $t30096, "#8a8a94", 2.5);
        }
      })();
      (() => {
        {
          const $t30097 = game.pickups;
          return draw_pickups(ctx, $t30097);
        }
      })();
      (() => {
        {
          const $t30098 = fx.trail;
          return draw_trail(ctx, $t30098, 0, 14);
        }
      })();
      (() => {
        {
          const $t30100 = fx.particles;
          return draw_particles(ctx, $t30100);
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
    const $t30102 = (() => {
      {
        const $t30101 = Perihelion$Combat$starkiller_target_idx(game);
        return Perihelion$Core$star_at(game, $t30101);
      }
    })();
    switch ($t30102.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f30108 = $t30102._0;
        {
          const s = $f30108;
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
              const $t30103 = s.x;
              {
                const $t30104 = s.y;
                {
                  const $t30106 = (() => {
                    {
                      const $t30105 = s.capture_radius;
                      return ($t30105 + 12.);
                    }
                  })();
                  return Canvas$arc(ctx, $t30103, $t30104, $t30106, 0., 6.28318530718);
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
      const $f30114 = points._0;
      const $f30115 = points._1;
      {
        const rest = (() => {
          return $f30115;
        })();
        {
          const pt = (() => {
            return $f30114;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              (() => {
                {
                  const $t30110 = (() => {
                    {
                      const $t30109 = march_int_mod(i, 3);
                      return ($t30109 === 0);
                    }
                  })();
                  if ($t30110 === true) {
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
                const $t30112 = (i + 1);
                return draw_trajectory_dots(ctx, rest, $t30112);
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
    const $t30126 = (() => {
      {
        const $t30123 = (() => {
          {
            const $t30122 = game.view_w;
            return (w === $t30122);
          }
        })();
        {
          const $t30125 = (() => {
            {
              const $t30124 = game.view_h;
              return (h === $t30124);
            }
          })();
          return ($t30123 && $t30125);
        }
      }
    })();
    if ($t30126 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          {
            const $t30128 = (() => {
              {
                const $t30127 = Math.trunc(w);
                return String($t30127);
              }
            })();
            return Dom$set_attr(el, "width", $t30128);
          }
        })();
        {
          const $t30130 = (() => {
            {
              const $t30129 = Math.trunc(h);
              return String($t30129);
            }
          })();
          return Dom$set_attr(el, "height", $t30130);
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
          const $t30144 = (() => {
            {
              const $t30142 = (() => {
                {
                  const $t30141 = game.phase;
                  switch ($t30141.$) {
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
                const $t30143 = (() => {
                  {
                    const $t30120_i5604 = g2.phase;
                    switch ($t30120_i5604.$) {
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
                return ($t30142 && $t30143);
              }
            }
          })();
          if ($t30144 === true) {
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
          const $t30149 = (() => {
            {
              const $t30146 = (() => {
                {
                  const $t30145 = game.mode;
                  switch ($t30145.$) {
                    case "Orbiting": {
                      const $f30131_i5600 = $t30145._0;
                      const $f30132_i5601 = $t30145._1;
                      const $f30133_i5602 = $t30145._2;
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
                const $t30148 = (() => {
                  {
                    const $t30147 = g2.mode;
                    switch ($t30147.$) {
                      case "Flying": {
                        const $f30134_i5597 = $t30147._0;
                        const $f30135_i5598 = $t30147._1;
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t30146 && $t30148);
              }
            }
          })();
          if ($t30149 === true) {
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
          const $t30150 = g2.capture_flash;
          switch ($t30150.$) {
            case "None": {
              return {  };
              break;
            }
            case "Some": {
              const $f30151 = $t30150._0;
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
          const $t30156 = (() => {
            {
              const $t30153 = (() => {
                {
                  const $t30152 = g2.player_shots;
                  {
                    const go_i5594 = { $: "$Clo_go$4837", _0: go$apply$4837 };
                    return go$apply$4837(go_i5594, $t30152, 0);
                  }
                }
              })();
              {
                const $t30155 = (() => {
                  {
                    const $t30154 = game.player_shots;
                    {
                      const go_i5592 = { $: "$Clo_go$4837", _0: go$apply$4837 };
                      return go$apply$4837(go_i5592, $t30154, 0);
                    }
                  }
                })();
                return ($t30153 > $t30155);
              }
            }
          })();
          if ($t30156 === true) {
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
          const $t30161 = (() => {
            {
              const $t30158 = (() => {
                {
                  const $t30157 = g2.enemy_shots;
                  {
                    const go_i5590 = { $: "$Clo_go$4837", _0: go$apply$4837 };
                    return go$apply$4837(go_i5590, $t30157, 0);
                  }
                }
              })();
              {
                const $t30160 = (() => {
                  {
                    const $t30159 = game.enemy_shots;
                    {
                      const go_i5588 = { $: "$Clo_go$4837", _0: go$apply$4837 };
                      return go$apply$4837(go_i5588, $t30159, 0);
                    }
                  }
                })();
                return ($t30158 > $t30160);
              }
            }
          })();
          if ($t30161 === true) {
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
          const $t30164 = (() => {
            {
              const $t30163 = (() => {
                {
                  const $t30162 = g2.fx_bursts;
                  switch ($t30162.$) {
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
              return (!$t30163);
            }
          })();
          if ($t30164 === true) {
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
          const $t30169 = (() => {
            {
              const $t30166 = (() => {
                {
                  const $t30165 = g2.ships;
                  {
                    const go_i5585 = { $: "$Clo_go$4789", _0: go$apply$4789 };
                    return go$apply$4789(go_i5585, $t30165, 0);
                  }
                }
              })();
              {
                const $t30168 = (() => {
                  {
                    const $t30167 = game.ships;
                    {
                      const go_i5583 = { $: "$Clo_go$4789", _0: go$apply$4789 };
                      return go$apply$4789(go_i5583, $t30167, 0);
                    }
                  }
                })();
                return ($t30166 < $t30168);
              }
            }
          })();
          if ($t30169 === true) {
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
          const $t30174 = (() => {
            {
              const $t30171 = (() => {
                {
                  const $t30170 = game.shield;
                  return ($t30170 === 0);
                }
              })();
              {
                const $t30173 = (() => {
                  {
                    const $t30172 = g2.shield;
                    return ($t30172 > 0);
                  }
                })();
                return ($t30171 && $t30173);
              }
            }
          })();
          if ($t30174 === true) {
            return (() => {
              return Audio$beep(actx, 700., 0.06, "sine");
            })();
          } else {
            return {  };
          }
        }
      })();
      {
        const $t30177 = (() => {
          {
            const $t30175 = (() => {
              {
                const $t30120_i5581 = game.phase;
                switch ($t30120_i5581.$) {
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
              const $t30176 = (() => {
                {
                  const $t30121_i5579 = g2.phase;
                  switch ($t30121_i5579.$) {
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
              return ($t30175 && $t30176);
            }
          }
        })();
        if ($t30177 === true) {
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
      const $f30183 = taps._0;
      const $f30184 = taps._1;
      {
        const tap = (() => {
          return $f30183;
        })();
        {
          const tx = tap._0;
          {
            const col_w = (view_w / 3.);
            {
              const idx = (() => {
                {
                  const $t30179 = (() => {
                    {
                      const $t30178 = tx;
                      return ($t30178 / col_w);
                    }
                  })();
                  return Math.trunc($t30179);
                }
              })();
              {
                const $t30181 = (() => {
                  {
                    const $t30180 = (idx > 2);
                    if ($t30180 === true) {
                      return 2;
                    } else {
                      return idx;
                    }
                  }
                })();
                return { $: "Some", _0: $t30181 };
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
          const $p30207 = dom_window_size();
          {
            const win_w = $p30207._0;
            {
              const win_h = $p30207._1;
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
                        const $t30189 = game.phase;
                        switch ($t30189.$) {
                          case "Milestone": {
                            {
                              const $jp_clo30195 = (() => {
                                return { $: "$Clo_$jp30194$3854", _0: $jp30194$apply$3854, _1: cursor, _2: game, _3: keys, _4: taps, _5: view_h, _6: view_w };
                              })();
                              {
                                const $t30190 = (() => {
                                  {
                                    const $t28706_i5616 = { $: "$Clo_$lam28703$3775", _0: $lam28703$apply$3775 };
                                    return List$any$List_String$Fn_String_Bool(keys, $t28706_i5616);
                                  }
                                })();
                                if ($t30190 === true) {
                                  return (() => {
                                    {
                                      const $rc_644 = (() => {
                                        return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                                      })();
                                      return $rc_644;
                                    }
                                  })();
                                } else {
                                  return (() => {
                                    {
                                      const $t30192 = (() => {
                                        {
                                          const $rc_645 = milestone_tap_choice(taps, view_w, view_h);
                                          return $rc_645;
                                        }
                                      })();
                                      return Perihelion$Core$pick_milestone(game, $t30192);
                                    }
                                  })();
                                }
                              }
                            }
                            break;
                          }
                          default: {
                            {
                              const $rc_646 = (() => {
                                return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                              })();
                              return $rc_646;
                            }
                          }
                        }
                      }
                    })();
                    {
                      const muted2 = (() => {
                        {
                          const $t30196 = fx.muted;
                          {
                            const $t30140_i5614 = (() => {
                              {
                                const $t30139_i5613 = { $: "$Clo_$lam30136$3852", _0: $lam30136$apply$3852 };
                                return List$any$List_String$Fn_String_Bool(keys, $t30139_i5613);
                              }
                            })();
                            if ($t30140_i5614 === true) {
                              return (!$t30196);
                            } else {
                              return $t30196;
                            }
                          }
                        }
                      })();
                      (() => {
                        {
                          const $t30197 = fx.actx;
                          return play_sfx($t30197, muted2, game, g2);
                        }
                      })();
                      {
                        const fx1 = step_fx(fx, g2, 0.0166667);
                        {
                          const fx2 = ({ ...fx1, muted: muted2 });
                          (() => {
                            {
                              const $t30201 = (() => {
                                {
                                  const $t30199 = (() => {
                                    {
                                      const $t30120_i5610 = game.phase;
                                      switch ($t30120_i5610.$) {
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
                                    const $t30200 = (() => {
                                      {
                                        const $t30121_i5608 = g2.phase;
                                        switch ($t30121_i5608.$) {
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
                                    return ($t30199 && $t30200);
                                  }
                                }
                              })();
                              if ($t30201 === true) {
                                return (() => {
                                  {
                                    const $t30204 = (() => {
                                      {
                                        const $t30202 = g2.best;
                                        {
                                          const $t30203 = g2.runs;
                                          return Perihelion$Core$encode_save($t30202, $t30203);
                                        }
                                      }
                                    })();
                                    return Dom$store_set("perihelion.v1", $t30204);
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
                            const $t30206 = { $: "$Clo_$lam30205$3855", _0: $lam30205$apply$3855, _1: ctx, _2: el, _3: fx2, _4: g2 };
                            return Dom$on_frame($t30206);
                          }
                        }
                      }
                    }
                  }
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
    const $p30213 = dom_window_size();
    {
      const win_w = $p30213._0;
      {
        const win_h = $p30213._1;
        {
          const view_w = win_w;
          {
            const view_h = win_h;
            (() => {
              {
                const $t30208 = String(win_w);
                return Dom$set_attr(node, "width", $t30208);
              }
            })();
            (() => {
              {
                const $t30209 = String(win_h);
                return Dom$set_attr(node, "height", $t30209);
              }
            })();
            {
              const $t30211 = (() => {
                {
                  const $t30210 = boot_seed();
                  return Perihelion$Core$fresh_run($t30210, best, runs, view_w, view_h);
                }
              })();
              {
                const $t30212 = (() => {
                  {
                    const $t29493_i5617 = { $: "Nil" };
                    {
                      const $t29494_i5618 = { $: "Nil" };
                      {
                        const $t29495_i5619 = { $: "None" };
                        {
                          const $t29496_i5620 = audio_create();
                          return ({ trail: $t29493_i5617, t: 0., particles: $t29494_i5618, flash: $t29495_i5619, actx: $t29496_i5620, muted: false });
                        }
                      }
                    }
                  }
                })();
                return tick(ctx, node, $t30211, $t30212);
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
    const $t30214 = Dom$find("game-canvas");
    switch ($t30214.$) {
      case "None": {
        return println$String("no #game-canvas found");
        break;
      }
      case "Some": {
        const $f30222 = $t30214._0;
        {
          const node = $f30222;
          {
            const $t30215 = (() => {
              return Canvas$get_context(node);
            })();
            switch ($t30215.$) {
              case "None": {
                return println$String("2d context unavailable");
                break;
              }
              case "Some": {
                const $f30221 = $t30215._0;
                {
                  const ctx = $f30221;
                  {
                    const saved = (() => {
                      {
                        const $t30216 = Dom$store_get("perihelion.v1");
                        switch ($t30216.$) {
                          case "None": {
                            return "";
                            break;
                          }
                          case "Some": {
                            const $f30217 = $t30216._0;
                            {
                              const sv = $f30217;
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
                      const $p30220 = (() => {
                        {
                          const $rc_647 = Perihelion$Core$decode_save(saved);
                          return $rc_647;
                        }
                      })();
                      {
                        const best = $p30220._0;
                        {
                          const runs = $p30220._1;
                          {
                            const $t30219 = (() => {
                              return { $: "$Clo_$lam30218$3856", _0: $lam30218$apply$3856, _1: best, _2: ctx, _3: node, _4: runs };
                            })();
                            return Dom$on_frame($t30219);
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
      const $t131 = x;
      {
        const $rc_659 = march_print(x);
        return $rc_659;
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
      const $f438 = xs._0;
      const $f439 = xs._1;
      {
        const t = $f439;
        {
          const h = $f438;
          {
            const $t437 = (() => {
              return pred._0(pred, h);
            })();
            if ($t437 === true) {
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
      const $f438 = xs._0;
      const $f439 = xs._1;
      {
        const t = $f439;
        {
          const h = $f438;
          {
            const $t437 = (() => {
              return pred._0(pred, h);
            })();
            if ($t437 === true) {
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
      const $f438 = xs._0;
      const $f439 = xs._1;
      {
        const t = $f439;
        {
          const h = $f438;
          {
            const $t437 = (() => {
              return pred._0(pred, h);
            })();
            if ($t437 === true) {
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
      const $f438 = xs._0;
      const $f439 = xs._1;
      {
        const t = $f439;
        {
          const h = $f438;
          {
            const $t437 = (() => {
              return pred._0(pred, h);
            })();
            if ($t437 === true) {
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
      const $f423 = xs._0;
      const $f424 = xs._1;
      {
        const t = $f424;
        {
          const h = $f423;
          {
            const $t422 = (() => {
              return pred._0(pred, h);
            })();
            if ($t422 === true) {
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
      const $f254 = xs._0;
      const $f255 = xs._1;
      {
        const t = $f255;
        {
          const h = $f254;
          {
            const $t252 = (n === 0);
            if ($t252 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t253 = (n - 1);
                  return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t253);
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
    const $t530 = (n <= 0);
    if ($t530 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f532 = xs._0;
            const $f533 = xs._1;
            {
              const t = $f533;
              {
                const $t531 = (n - 1);
                return List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(t, $t531);
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
      const $f254 = xs._0;
      const $f255 = xs._1;
      {
        const t = $f255;
        {
          const h = $f254;
          {
            const $t252 = (n === 0);
            if ($t252 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t253 = (n - 1);
                  return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int(t, $t253);
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
      const $f254 = xs._0;
      const $f255 = xs._1;
      {
        const t = $f255;
        {
          const h = $f254;
          {
            const $t252 = (n === 0);
            if ($t252 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t253 = (n - 1);
                  return List$nth_opt$List_WeaponKind$Int(t, $t253);
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
      const $f254 = xs._0;
      const $f255 = xs._1;
      {
        const t = $f255;
        {
          const h = $f254;
          {
            const $t252 = (n === 0);
            if ($t252 === true) {
              return { $: "Some", _0: h };
            } else {
              return (() => {
                {
                  const $t253 = (n - 1);
                  return List$nth_opt$List_UpgradeKind$Int(t, $t253);
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
    const $t530 = (n <= 0);
    if ($t530 === true) {
      return xs;
    } else {
      return (() => {
        switch (xs.$) {
          case "Nil": {
            return { $: "Nil" };
            break;
          }
          case "Cons": {
            const $f532 = xs._0;
            const $f533 = xs._1;
            {
              const t = $f533;
              {
                const $t531 = (n - 1);
                return List$drop$List_UpgradeKind$Int(t, $t531);
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
      const $f246 = xs._0;
      const $f247 = xs._1;
      {
        const t = $f247;
        {
          const h = $f246;
          {
            const $t244 = (n === 0);
            if ($t244 === true) {
              return h;
            } else {
              return (() => {
                {
                  const $t245 = (n - 1);
                  return List$nth$List_UpgradeKind$Int(t, $t245);
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
      const $f438 = xs._0;
      const $f439 = xs._1;
      {
        const t = $f439;
        {
          const h = $f438;
          {
            const $t437 = (() => {
              return pred._0(pred, h);
            })();
            if ($t437 === true) {
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

function $lam27758$apply$3709($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27759 = g1.asteroids;
        {
          const $t27760 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27759, $t27760);
        }
      }
    }
  }
}
const $lam27758$apply$3709$clo = { _0: ($_, $clo, s) => $lam27758$apply$3709($clo, s) };

function $lam27763$apply$3710($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27765 = (() => {
        {
          const $t27764 = s.ttl;
          return ($t27764 > 0.);
        }
      })();
      {
        const $t27768 = (() => {
          {
            const $t27766 = s.x;
            {
              const $t27767 = s.y;
              return Perihelion$Combat$in_band(g1, $t27766, $t27767);
            }
          }
        })();
        return ($t27765 && $t27768);
      }
    }
  }
}
const $lam27763$apply$3710$clo = { _0: ($_, $clo, s) => $lam27763$apply$3710($clo, s) };

function $lam27771$apply$3711($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27772 = g1.asteroids;
        {
          const $t27773 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27772, $t27773);
        }
      }
    }
  }
}
const $lam27771$apply$3711$clo = { _0: ($_, $clo, s) => $lam27771$apply$3711($clo, s) };

function $lam27776$apply$3712($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27778 = (() => {
        {
          const $t27777 = s.ttl;
          return ($t27777 > 0.);
        }
      })();
      {
        const $t27781 = (() => {
          {
            const $t27779 = s.x;
            {
              const $t27780 = s.y;
              return Perihelion$Combat$in_band(g1, $t27779, $t27780);
            }
          }
        })();
        return ($t27778 && $t27781);
      }
    }
  }
}
const $lam27776$apply$3712$clo = { _0: ($_, $clo, s) => $lam27776$apply$3712($clo, s) };

function $lam27784$apply$3713($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27786 = (() => {
        {
          const $t27785 = p.ttl;
          return ($t27785 - dt_s);
        }
      })();
      return ({ ...p, ttl: $t27786 });
    }
  }
}
const $lam27784$apply$3713$clo = { _0: ($_, $clo, p) => $lam27784$apply$3713($clo, p) };

function $lam27789$apply$3714($clo, p) {
  {
    const $t27790 = p.ttl;
    return ($t27790 > 0.);
  }
}
const $lam27789$apply$3714$clo = { _0: ($_, $clo, p) => $lam27789$apply$3714($clo, p) };

function $lam28189$apply$3730($clo, k) {
  return (k === " ");
}
const $lam28189$apply$3730$clo = { _0: ($_, $clo, k) => $lam28189$apply$3730($clo, k) };

function $lam28257$apply$3733($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28258 = sh.star_idx;
      return ($t28258 !== tidx);
    }
  }
}
const $lam28257$apply$3733$clo = { _0: ($_, $clo, sh) => $lam28257$apply$3733($clo, sh) };

function $lam28261$apply$3734($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28263 = (() => {
        {
          const $t28262 = sh.star_idx;
          return ($t28262 > tidx);
        }
      })();
      if ($t28263 === true) {
        return (() => {
          {
            const $t28265 = (() => {
              {
                const $t28264 = sh.star_idx;
                return ($t28264 - 1);
              }
            })();
            return ({ ...sh, star_idx: $t28265 });
          }
        })();
      } else {
        return sh;
      }
    }
  }
}
const $lam28261$apply$3734$clo = { _0: ($_, $clo, sh) => $lam28261$apply$3734($clo, sh) };

function $lam28278$apply$3736($clo, s) {
  return s.star_killer;
}
const $lam28278$apply$3736$clo = { _0: ($_, $clo, s) => $lam28278$apply$3736($clo, s) };

function $lam28291$apply$3738($clo, sh) {
  {
    const $t28292 = sh.star_killer;
    return (!$t28292);
  }
}
const $lam28291$apply$3738$clo = { _0: ($_, $clo, sh) => $lam28291$apply$3738($clo, sh) };

function $lam28298$apply$3739($clo, sh) {
  {
    const $t28299 = sh.star_killer;
    return (!$t28299);
  }
}
const $lam28298$apply$3739$clo = { _0: ($_, $clo, sh) => $lam28298$apply$3739($clo, sh) };

function $lam28312$apply$3740($clo, a) {
  {
    const $t28313 = a.x;
    {
      const $t28314 = a.y;
      return { _0: $t28313, _1: $t28314 };
    }
  }
}
const $lam28312$apply$3740$clo = { _0: ($_, $clo, a) => $lam28312$apply$3740($clo, a) };

function $lam28317$apply$3741($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28318 = game.player_shots;
      {
        const $t28323 = { $: "$Clo_$lam28319$3742", _0: $lam28319$apply$3742, _1: a };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28318, $t28323);
      }
    }
  }
}
const $lam28317$apply$3741$clo = { _0: ($_, $clo, a) => $lam28317$apply$3741($clo, a) };

function $lam28319$apply$3742($clo, s) {
  {
    const a = (() => {
      return $clo._1;
    })();
    {
      const $t28320 = a.x;
      {
        const $t28321 = a.y;
        {
          const $t28322 = a.radius;
          {
            const $t28309_i9569 = s.x;
            {
              const $t28310_i9570 = s.y;
              {
                const $t27627_i12327 = (() => {
                  {
                    const dx_i4486_i12323 = ($t28320 - $t28309_i9569);
                    {
                      const dy_i4487_i12324 = ($t28321 - $t28310_i9570);
                      {
                        const $t27625_i4488_i12325 = (dx_i4486_i12323 * dx_i4486_i12323);
                        {
                          const $t27626_i4489_i12326 = (dy_i4487_i12324 * dy_i4487_i12324);
                          return ($t27625_i4488_i12325 + $t27626_i4489_i12326);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i12330 = (() => {
                    {
                      const $t27628_i12328 = (3. + $t28322);
                      {
                        const $t27629_i12329 = (3. + $t28322);
                        return ($t27628_i12328 * $t27629_i12329);
                      }
                    }
                  })();
                  return ($t27627_i12327 <= $t27630_i12330);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28319$apply$3742$clo = { _0: ($_, $clo, s) => $lam28319$apply$3742($clo, s) };

function $lam28326$apply$3743($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28333 = (() => {
        {
          const $t28327 = game.asteroids;
          {
            const $t28332 = { $: "$Clo_$lam28328$3744", _0: $lam28328$apply$3744, _1: s };
            return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28327, $t28332);
          }
        }
      })();
      return (!$t28333);
    }
  }
}
const $lam28326$apply$3743$clo = { _0: ($_, $clo, s) => $lam28326$apply$3743($clo, s) };

function $lam28328$apply$3744($clo, a) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const $t28329 = a.x;
      {
        const $t28330 = a.y;
        {
          const $t28331 = a.radius;
          {
            const $t28309_i9576 = s.x;
            {
              const $t28310_i9577 = s.y;
              {
                const $t27627_i12341 = (() => {
                  {
                    const dx_i4486_i12337 = ($t28329 - $t28309_i9576);
                    {
                      const dy_i4487_i12338 = ($t28330 - $t28310_i9577);
                      {
                        const $t27625_i4488_i12339 = (dx_i4486_i12337 * dx_i4486_i12337);
                        {
                          const $t27626_i4489_i12340 = (dy_i4487_i12338 * dy_i4487_i12338);
                          return ($t27625_i4488_i12339 + $t27626_i4489_i12340);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i12344 = (() => {
                    {
                      const $t27628_i12342 = (3. + $t28331);
                      {
                        const $t27629_i12343 = (3. + $t28331);
                        return ($t27628_i12342 * $t27629_i12343);
                      }
                    }
                  })();
                  return ($t27627_i12341 <= $t27630_i12344);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28328$apply$3744$clo = { _0: ($_, $clo, a) => $lam28328$apply$3744($clo, a) };

function $lam28345$apply$3745($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28346 = game.player_shots;
      {
        const $t28348 = { $: "$Clo_$lam28347$3746", _0: $lam28347$apply$3746, _1: sh };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28346, $t28348);
      }
    }
  }
}
const $lam28345$apply$3745$clo = { _0: ($_, $clo, sh) => $lam28345$apply$3745($clo, sh) };

function $lam28347$apply$3746($clo, s) {
  {
    const sh = (() => {
      return $clo._1;
    })();
    {
      const pos_i9581 = (() => {
        {
          const pos_i12358 = (() => {
            {
              const $t27623_i12356 = sh.x;
              {
                const $t27624_i12357 = sh.y;
                return { _0: $t27623_i12356, _1: $t27624_i12357 };
              }
            }
          })();
          return pos_i12358;
        }
      })();
      {
        const sx_i9583 = pos_i9581._0;
        {
          const sy_i9584 = pos_i9581._1;
          {
            const $t28309_i12349 = s.x;
            {
              const $t28310_i12350 = s.y;
              {
                const $t27627_i4783_i12351 = (() => {
                  {
                    const dx_i12770 = (sx_i9583 - $t28309_i12349);
                    {
                      const dy_i12771 = (sy_i9584 - $t28310_i12350);
                      {
                        const $t27625_i12772 = (dx_i12770 * dx_i12770);
                        {
                          const $t27626_i12773 = (dy_i12771 * dy_i12771);
                          return ($t27625_i12772 + $t27626_i12773);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i4786_i12354 = (() => {
                    {
                      const $t27628_i4784_i12352 = (3. + 10.);
                      {
                        const $t27629_i4785_i12353 = (3. + 10.);
                        return ($t27628_i4784_i12352 * $t27629_i4785_i12353);
                      }
                    }
                  })();
                  return ($t27627_i4783_i12351 <= $t27630_i4786_i12354);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28347$apply$3746$clo = { _0: ($_, $clo, s) => $lam28347$apply$3746($clo, s) };

function $lam28351$apply$3747($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28355 = (() => {
        {
          const $t28352 = game.ships;
          {
            const $t28354 = { $: "$Clo_$lam28353$3748", _0: $lam28353$apply$3748, _1: s };
            return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28352, $t28354);
          }
        }
      })();
      return (!$t28355);
    }
  }
}
const $lam28351$apply$3747$clo = { _0: ($_, $clo, s) => $lam28351$apply$3747($clo, s) };

function $lam28353$apply$3748($clo, sh) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const pos_i9588 = (() => {
        {
          const pos_i12372 = (() => {
            {
              const $t27623_i12370 = sh.x;
              {
                const $t27624_i12371 = sh.y;
                return { _0: $t27623_i12370, _1: $t27624_i12371 };
              }
            }
          })();
          return pos_i12372;
        }
      })();
      {
        const sx_i9590 = pos_i9588._0;
        {
          const sy_i9591 = pos_i9588._1;
          {
            const $t28309_i12363 = s.x;
            {
              const $t28310_i12364 = s.y;
              {
                const $t27627_i4783_i12365 = (() => {
                  {
                    const dx_i12778 = (sx_i9590 - $t28309_i12363);
                    {
                      const dy_i12779 = (sy_i9591 - $t28310_i12364);
                      {
                        const $t27625_i12780 = (dx_i12778 * dx_i12778);
                        {
                          const $t27626_i12781 = (dy_i12779 * dy_i12779);
                          return ($t27625_i12780 + $t27626_i12781);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i4786_i12368 = (() => {
                    {
                      const $t27628_i4784_i12366 = (3. + 10.);
                      {
                        const $t27629_i4785_i12367 = (3. + 10.);
                        return ($t27628_i4784_i12366 * $t27629_i4785_i12367);
                      }
                    }
                  })();
                  return ($t27627_i4783_i12365 <= $t27630_i4786_i12368);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28353$apply$3748$clo = { _0: ($_, $clo, sh) => $lam28353$apply$3748($clo, sh) };

function $lam28402$apply$3750($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28395_i9596 = p.x;
      {
        const $t28396_i9597 = p.y;
        {
          const $t28398_i9599 = game.ball_x;
          {
            const $t28399_i9600 = game.ball_y;
            {
              const $t27627_i12383 = (() => {
                {
                  const dx_i4486_i12379 = ($t28398_i9599 - $t28395_i9596);
                  {
                    const dy_i4487_i12380 = ($t28399_i9600 - $t28396_i9597);
                    {
                      const $t27625_i4488_i12381 = (dx_i4486_i12379 * dx_i4486_i12379);
                      {
                        const $t27626_i4489_i12382 = (dy_i4487_i12380 * dy_i4487_i12380);
                        return ($t27625_i4488_i12381 + $t27626_i4489_i12382);
                      }
                    }
                  }
                }
              })();
              {
                const $t27630_i12386 = (() => {
                  {
                    const $t27628_i12384 = (12. + 6.);
                    {
                      const $t27629_i12385 = (12. + 6.);
                      return ($t27628_i12384 * $t27629_i12385);
                    }
                  }
                })();
                return ($t27627_i12383 <= $t27630_i12386);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28402$apply$3750$clo = { _0: ($_, $clo, p) => $lam28402$apply$3750($clo, p) };

function $lam28406$apply$3751($clo, q) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28407 = (() => {
        {
          const $t28395_i9604 = q.x;
          {
            const $t28396_i9605 = q.y;
            {
              const $t28398_i9607 = game.ball_x;
              {
                const $t28399_i9608 = game.ball_y;
                {
                  const $t27627_i12397 = (() => {
                    {
                      const dx_i4486_i12393 = ($t28398_i9607 - $t28395_i9604);
                      {
                        const dy_i4487_i12394 = ($t28399_i9608 - $t28396_i9605);
                        {
                          const $t27625_i4488_i12395 = (dx_i4486_i12393 * dx_i4486_i12393);
                          {
                            const $t27626_i4489_i12396 = (dy_i4487_i12394 * dy_i4487_i12394);
                            return ($t27625_i4488_i12395 + $t27626_i4489_i12396);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27630_i12400 = (() => {
                      {
                        const $t27628_i12398 = (12. + 6.);
                        {
                          const $t27629_i12399 = (12. + 6.);
                          return ($t27628_i12398 * $t27629_i12399);
                        }
                      }
                    })();
                    return ($t27627_i12397 <= $t27630_i12400);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28407);
    }
  }
}
const $lam28406$apply$3751$clo = { _0: ($_, $clo, q) => $lam28406$apply$3751($clo, q) };

function $jp28424$apply$3752($clo) {
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
          const $t28422 = (() => {
            {
              const $t28421 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28421);
            }
          })();
          return ({ ...$t28422, pickups: remaining });
        }
      }
    }
  }
}
const $jp28424$apply$3752$clo = { _0: ($_, $clo) => $jp28424$apply$3752($clo) };

function $jp28428$apply$3753($clo) {
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
          const $t28422 = (() => {
            {
              const $t28421 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28421);
            }
          })();
          return ({ ...$t28422, pickups: remaining });
        }
      }
    }
  }
}
const $jp28428$apply$3753$clo = { _0: ($_, $clo) => $jp28428$apply$3753($clo) };

function $lam28449$apply$3754($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28442_i9612 = game.ball_x;
      {
        const $t28443_i9613 = game.ball_y;
        {
          const $t28309_i12405 = s.x;
          {
            const $t28310_i12406 = s.y;
            {
              const $t27627_i4783_i12407 = (() => {
                {
                  const dx_i12786 = ($t28442_i9612 - $t28309_i12405);
                  {
                    const dy_i12787 = ($t28443_i9613 - $t28310_i12406);
                    {
                      const $t27625_i12788 = (dx_i12786 * dx_i12786);
                      {
                        const $t27626_i12789 = (dy_i12787 * dy_i12787);
                        return ($t27625_i12788 + $t27626_i12789);
                      }
                    }
                  }
                }
              })();
              {
                const $t27630_i4786_i12410 = (() => {
                  {
                    const $t27628_i4784_i12408 = (3. + 6.);
                    {
                      const $t27629_i4785_i12409 = (3. + 6.);
                      return ($t27628_i4784_i12408 * $t27629_i4785_i12409);
                    }
                  }
                })();
                return ($t27627_i4783_i12407 <= $t27630_i4786_i12410);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28449$apply$3754$clo = { _0: ($_, $clo, s) => $lam28449$apply$3754($clo, s) };

function $lam28454$apply$3755($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28455 = (() => {
        {
          const $t28442_i9617 = game.ball_x;
          {
            const $t28443_i9618 = game.ball_y;
            {
              const $t28309_i12415 = s.x;
              {
                const $t28310_i12416 = s.y;
                {
                  const $t27627_i4783_i12417 = (() => {
                    {
                      const dx_i12794 = ($t28442_i9617 - $t28309_i12415);
                      {
                        const dy_i12795 = ($t28443_i9618 - $t28310_i12416);
                        {
                          const $t27625_i12796 = (dx_i12794 * dx_i12794);
                          {
                            const $t27626_i12797 = (dy_i12795 * dy_i12795);
                            return ($t27625_i12796 + $t27626_i12797);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27630_i4786_i12420 = (() => {
                      {
                        const $t27628_i4784_i12418 = (3. + 6.);
                        {
                          const $t27629_i4785_i12419 = (3. + 6.);
                          return ($t27628_i4784_i12418 * $t27629_i4785_i12419);
                        }
                      }
                    })();
                    return ($t27627_i4783_i12417 <= $t27630_i4786_i12420);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28455);
    }
  }
}
const $lam28454$apply$3755$clo = { _0: ($_, $clo, s) => $lam28454$apply$3755($clo, s) };

function $lam28459$apply$3756($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28436_i9622 = a.x;
      {
        const $t28437_i9623 = a.y;
        {
          const $t28438_i9624 = a.radius;
          {
            const $t28439_i9625 = game.ball_x;
            {
              const $t28440_i9626 = game.ball_y;
              {
                const $t27627_i12431 = (() => {
                  {
                    const dx_i4486_i12427 = ($t28439_i9625 - $t28436_i9622);
                    {
                      const dy_i4487_i12428 = ($t28440_i9626 - $t28437_i9623);
                      {
                        const $t27625_i4488_i12429 = (dx_i4486_i12427 * dx_i4486_i12427);
                        {
                          const $t27626_i4489_i12430 = (dy_i4487_i12428 * dy_i4487_i12428);
                          return ($t27625_i4488_i12429 + $t27626_i4489_i12430);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i12434 = (() => {
                    {
                      const $t27628_i12432 = ($t28438_i9624 + 6.);
                      {
                        const $t27629_i12433 = ($t28438_i9624 + 6.);
                        return ($t27628_i12432 * $t27629_i12433);
                      }
                    }
                  })();
                  return ($t27627_i12431 <= $t27630_i12434);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28459$apply$3756$clo = { _0: ($_, $clo, a) => $lam28459$apply$3756($clo, a) };

function $lam28462$apply$3757($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const pos_i9630 = (() => {
        {
          const pos_i12452 = (() => {
            {
              const $t27623_i12450 = sh.x;
              {
                const $t27624_i12451 = sh.y;
                return { _0: $t27623_i12450, _1: $t27624_i12451 };
              }
            }
          })();
          return pos_i12452;
        }
      })();
      {
        const sx_i9632 = pos_i9630._0;
        {
          const sy_i9633 = pos_i9630._1;
          {
            const $t28432_i9635 = game.ball_x;
            {
              const $t28433_i9636 = game.ball_y;
              {
                const $t27627_i12445 = (() => {
                  {
                    const dx_i4486_i12441 = ($t28432_i9635 - sx_i9632);
                    {
                      const dy_i4487_i12442 = ($t28433_i9636 - sy_i9633);
                      {
                        const $t27625_i4488_i12443 = (dx_i4486_i12441 * dx_i4486_i12441);
                        {
                          const $t27626_i4489_i12444 = (dy_i4487_i12442 * dy_i4487_i12442);
                          return ($t27625_i4488_i12443 + $t27626_i4489_i12444);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i12448 = (() => {
                    {
                      const $t27628_i12446 = (10. + 6.);
                      {
                        const $t27629_i12447 = (10. + 6.);
                        return ($t27628_i12446 * $t27629_i12447);
                      }
                    }
                  })();
                  return ($t27627_i12445 <= $t27630_i12448);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28462$apply$3757$clo = { _0: ($_, $clo, sh) => $lam28462$apply$3757($clo, sh) };

function $lam28478$apply$3758($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28436_i9640 = a.x;
      {
        const $t28437_i9641 = a.y;
        {
          const $t28438_i9642 = a.radius;
          {
            const $t28439_i9643 = game.ball_x;
            {
              const $t28440_i9644 = game.ball_y;
              {
                const $t27627_i12463 = (() => {
                  {
                    const dx_i4486_i12459 = ($t28439_i9643 - $t28436_i9640);
                    {
                      const dy_i4487_i12460 = ($t28440_i9644 - $t28437_i9641);
                      {
                        const $t27625_i4488_i12461 = (dx_i4486_i12459 * dx_i4486_i12459);
                        {
                          const $t27626_i4489_i12462 = (dy_i4487_i12460 * dy_i4487_i12460);
                          return ($t27625_i4488_i12461 + $t27626_i4489_i12462);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27630_i12466 = (() => {
                    {
                      const $t27628_i12464 = ($t28438_i9642 + 6.);
                      {
                        const $t27629_i12465 = ($t28438_i9642 + 6.);
                        return ($t27628_i12464 * $t27629_i12465);
                      }
                    }
                  })();
                  return ($t27627_i12463 <= $t27630_i12466);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28478$apply$3758$clo = { _0: ($_, $clo, a) => $lam28478$apply$3758($clo, a) };

function $lam28483$apply$3759($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28484 = (() => {
        {
          const $t28436_i9648 = a.x;
          {
            const $t28437_i9649 = a.y;
            {
              const $t28438_i9650 = a.radius;
              {
                const $t28439_i9651 = game.ball_x;
                {
                  const $t28440_i9652 = game.ball_y;
                  {
                    const $t27627_i12477 = (() => {
                      {
                        const dx_i4486_i12473 = ($t28439_i9651 - $t28436_i9648);
                        {
                          const dy_i4487_i12474 = ($t28440_i9652 - $t28437_i9649);
                          {
                            const $t27625_i4488_i12475 = (dx_i4486_i12473 * dx_i4486_i12473);
                            {
                              const $t27626_i4489_i12476 = (dy_i4487_i12474 * dy_i4487_i12474);
                              return ($t27625_i4488_i12475 + $t27626_i4489_i12476);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27630_i12480 = (() => {
                        {
                          const $t27628_i12478 = ($t28438_i9650 + 6.);
                          {
                            const $t27629_i12479 = ($t28438_i9650 + 6.);
                            return ($t27628_i12478 * $t27629_i12479);
                          }
                        }
                      })();
                      return ($t27627_i12477 <= $t27630_i12480);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28484);
    }
  }
}
const $lam28483$apply$3759$clo = { _0: ($_, $clo, a) => $lam28483$apply$3759($clo, a) };

function $lam28488$apply$3760($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28489 = (() => {
        {
          const $t28442_i9656 = game.ball_x;
          {
            const $t28443_i9657 = game.ball_y;
            {
              const $t28309_i12485 = s.x;
              {
                const $t28310_i12486 = s.y;
                {
                  const $t27627_i4783_i12487 = (() => {
                    {
                      const dx_i12802 = ($t28442_i9656 - $t28309_i12485);
                      {
                        const dy_i12803 = ($t28443_i9657 - $t28310_i12486);
                        {
                          const $t27625_i12804 = (dx_i12802 * dx_i12802);
                          {
                            const $t27626_i12805 = (dy_i12803 * dy_i12803);
                            return ($t27625_i12804 + $t27626_i12805);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27630_i4786_i12490 = (() => {
                      {
                        const $t27628_i4784_i12488 = (3. + 6.);
                        {
                          const $t27629_i4785_i12489 = (3. + 6.);
                          return ($t27628_i4784_i12488 * $t27629_i4785_i12489);
                        }
                      }
                    })();
                    return ($t27627_i4783_i12487 <= $t27630_i4786_i12490);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28489);
    }
  }
}
const $lam28488$apply$3760$clo = { _0: ($_, $clo, s) => $lam28488$apply$3760($clo, s) };

function $lam28493$apply$3761($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28494 = (() => {
        {
          const pos_i9661 = (() => {
            {
              const pos_i12508 = (() => {
                {
                  const $t27623_i12506 = sh.x;
                  {
                    const $t27624_i12507 = sh.y;
                    return { _0: $t27623_i12506, _1: $t27624_i12507 };
                  }
                }
              })();
              return pos_i12508;
            }
          })();
          {
            const sx_i9663 = pos_i9661._0;
            {
              const sy_i9664 = pos_i9661._1;
              {
                const $t28432_i9666 = game.ball_x;
                {
                  const $t28433_i9667 = game.ball_y;
                  {
                    const $t27627_i12501 = (() => {
                      {
                        const dx_i4486_i12497 = ($t28432_i9666 - sx_i9663);
                        {
                          const dy_i4487_i12498 = ($t28433_i9667 - sy_i9664);
                          {
                            const $t27625_i4488_i12499 = (dx_i4486_i12497 * dx_i4486_i12497);
                            {
                              const $t27626_i4489_i12500 = (dy_i4487_i12498 * dy_i4487_i12498);
                              return ($t27625_i4488_i12499 + $t27626_i4489_i12500);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27630_i12504 = (() => {
                        {
                          const $t27628_i12502 = (10. + 6.);
                          {
                            const $t27629_i12503 = (10. + 6.);
                            return ($t27628_i12502 * $t27629_i12503);
                          }
                        }
                      })();
                      return ($t27627_i12501 <= $t27630_i12504);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28494);
    }
  }
}
const $lam28493$apply$3761$clo = { _0: ($_, $clo, sh) => $lam28493$apply$3761($clo, sh) };

function $lam28575$apply$3762($clo, k) {
  {
    const $t28576 = (() => {
      return (k === "w");
    })();
    {
      const $t28577 = (k === "W");
      return ($t28576 || $t28577);
    }
  }
}
const $lam28575$apply$3762$clo = { _0: ($_, $clo, k) => $lam28575$apply$3762($clo, k) };

function $lam28579$apply$3763($clo, k) {
  {
    const $t28580 = (() => {
      return (k === "s");
    })();
    {
      const $t28581 = (k === "S");
      return ($t28580 || $t28581);
    }
  }
}
const $lam28579$apply$3763$clo = { _0: ($_, $clo, k) => $lam28579$apply$3763($clo, k) };

function $lam28594$apply$3764($clo, k) {
  {
    const $t28595 = (() => {
      return (k === "e");
    })();
    {
      const $t28596 = (k === "E");
      return ($t28595 || $t28596);
    }
  }
}
const $lam28594$apply$3764$clo = { _0: ($_, $clo, k) => $lam28594$apply$3764($clo, k) };

function $lam28598$apply$3765($clo, k) {
  {
    const $t28599 = (() => {
      return (k === "q");
    })();
    {
      const $t28600 = (k === "Q");
      return ($t28599 || $t28600);
    }
  }
}
const $lam28598$apply$3765$clo = { _0: ($_, $clo, k) => $lam28598$apply$3765($clo, k) };

function $lam28606$apply$3766($clo, k) {
  {
    const $t28607 = (() => {
      return (k === "d");
    })();
    {
      const $t28608 = (k === "D");
      return ($t28607 || $t28608);
    }
  }
}
const $lam28606$apply$3766$clo = { _0: ($_, $clo, k) => $lam28606$apply$3766($clo, k) };

function $lam28610$apply$3767($clo, k) {
  {
    const $t28611 = (() => {
      return (k === "w");
    })();
    {
      const $t28612 = (k === "W");
      return ($t28611 || $t28612);
    }
  }
}
const $lam28610$apply$3767$clo = { _0: ($_, $clo, k) => $lam28610$apply$3767($clo, k) };

function $lam28663$apply$3770($clo, k) {
  {
    const $t28664 = (() => {
      return (k === "x");
    })();
    {
      const $t28665 = (k === "X");
      return ($t28664 || $t28665);
    }
  }
}
const $lam28663$apply$3770$clo = { _0: ($_, $clo, k) => $lam28663$apply$3770($clo, k) };

function $lam28703$apply$3775($clo, k) {
  {
    const $t28704 = (() => {
      return (k === "r");
    })();
    {
      const $t28705 = (k === "R");
      return ($t28704 || $t28705);
    }
  }
}
const $lam28703$apply$3775$clo = { _0: ($_, $clo, k) => $lam28703$apply$3775($clo, k) };

function $jp29016$apply$3787($clo) {
  {
    const $f29011 = (() => {
      return $clo._1;
    })();
    {
      const fallback = (() => {
        return $clo._2;
      })();
      {
        const rest = (() => {
          return $f29011;
        })();
        return Perihelion$Core$top_star(rest, fallback);
      }
    }
  }
}
const $jp29016$apply$3787$clo = { _0: ($_, $clo) => $jp29016$apply$3787($clo) };

function $lam29218$apply$3799($clo, r) {
  return Perihelion$Core$encode_run(r);
}
const $lam29218$apply$3799$clo = { _0: ($_, $clo, r) => $lam29218$apply$3799($clo, r) };

function $jp29232$apply$3800($clo) {
  return { $: "None" };
}
const $jp29232$apply$3800$clo = { _0: ($_, $clo) => $jp29232$apply$3800($clo) };

function $jp29236$apply$3801($clo) {
  {
    const $jp_clo29233 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29235 = (() => {
        return { $: "$Clo_$jp29234$3802", _0: $jp29234$apply$3802, _1: $jp_clo29233 };
      })();
      return $jp29234$apply$3802($jp_clo29235);
    }
  }
}
const $jp29236$apply$3801$clo = { _0: ($_, $clo) => $jp29236$apply$3801($clo) };

function $jp29234$apply$3802($clo) {
  {
    const $jp_clo29233 = (() => {
      return $clo._1;
    })();
    return $jp_clo29233._0($jp_clo29233);
  }
}
const $jp29234$apply$3802$clo = { _0: ($_, $clo) => $jp29234$apply$3802($clo) };

function $jp29240$apply$3803($clo) {
  {
    const $jp_clo29237 = (() => {
      return $clo._1;
    })();
    return $jp_clo29237._0($jp_clo29237);
  }
}
const $jp29240$apply$3803$clo = { _0: ($_, $clo) => $jp29240$apply$3803($clo) };

function $jp29244$apply$3804($clo) {
  {
    const $jp_clo29241 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29243 = (() => {
        return { $: "$Clo_$jp29242$3805", _0: $jp29242$apply$3805, _1: $jp_clo29241 };
      })();
      return $jp29242$apply$3805($jp_clo29243);
    }
  }
}
const $jp29244$apply$3804$clo = { _0: ($_, $clo) => $jp29244$apply$3804($clo) };

function $jp29242$apply$3805($clo) {
  {
    const $jp_clo29241 = (() => {
      return $clo._1;
    })();
    return $jp_clo29241._0($jp_clo29241);
  }
}
const $jp29242$apply$3805$clo = { _0: ($_, $clo) => $jp29242$apply$3805($clo) };

function $jp29248$apply$3806($clo) {
  {
    const $jp_clo29245 = (() => {
      return $clo._1;
    })();
    return $jp_clo29245._0($jp_clo29245);
  }
}
const $jp29248$apply$3806$clo = { _0: ($_, $clo) => $jp29248$apply$3806($clo) };

function $jp29252$apply$3807($clo) {
  {
    const $jp_clo29249 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29251 = (() => {
        return { $: "$Clo_$jp29250$3808", _0: $jp29250$apply$3808, _1: $jp_clo29249 };
      })();
      return $jp29250$apply$3808($jp_clo29251);
    }
  }
}
const $jp29252$apply$3807$clo = { _0: ($_, $clo) => $jp29252$apply$3807($clo) };

function $jp29250$apply$3808($clo) {
  {
    const $jp_clo29249 = (() => {
      return $clo._1;
    })();
    return $jp_clo29249._0($jp_clo29249);
  }
}
const $jp29250$apply$3808$clo = { _0: ($_, $clo) => $jp29250$apply$3808($clo) };

function $lam29442$apply$3817($clo, u) {
  {
    const owned = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29444 = u._0;
        {
          const k = $f29444;
          {
            const $t29443 = (() => {
              {
                const $t690_i9695 = { $: "$Clo_$lam689$4794", _0: $lam689$apply$4794, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool(owned, $t690_i9695);
              }
            })();
            return (!$t29443);
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
const $lam29442$apply$3817$clo = { _0: ($_, $clo, u) => $lam29442$apply$3817($clo, u) };

function $lam29480$apply$3818($clo, u) {
  {
    const k = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "SpecialItem": {
        const $f29481 = u._0;
        {
          const sk = $f29481;
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
const $lam29480$apply$3818$clo = { _0: ($_, $clo, u) => $lam29480$apply$3818($clo, u) };

function $lam29538$apply$3820($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t29531_i9702 = (() => {
        {
          const $t29528_i9699 = p.x;
          {
            const $t29530_i9701 = (() => {
              {
                const $t29529_i9700 = p.vx;
                return ($t29529_i9700 * dt_s);
              }
            })();
            return ($t29528_i9699 + $t29530_i9701);
          }
        }
      })();
      {
        const $t29535_i9706 = (() => {
          {
            const $t29532_i9703 = p.y;
            {
              const $t29534_i9705 = (() => {
                {
                  const $t29533_i9704 = p.vy;
                  return ($t29533_i9704 * dt_s);
                }
              })();
              return ($t29532_i9703 + $t29534_i9705);
            }
          }
        })();
        {
          const $t29537_i9708 = (() => {
            {
              const $t29536_i9707 = p.life;
              return ($t29536_i9707 - dt_s);
            }
          })();
          return ({ ...p, x: $t29531_i9702, y: $t29535_i9706, life: $t29537_i9708 });
        }
      }
    }
  }
}
const $lam29538$apply$3820$clo = { _0: ($_, $clo, p) => $lam29538$apply$3820($clo, p) };

function $lam29541$apply$3821($clo, p) {
  {
    const $t29542 = p.life;
    return ($t29542 > 0.);
  }
}
const $lam29541$apply$3821$clo = { _0: ($_, $clo, p) => $lam29541$apply$3821($clo, p) };

function $jp29687$apply$3824($clo) {
  {
    const $f29681 = (() => {
      return $clo._1;
    })();
    {
      const $f29682 = (() => {
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
              return $f29682;
            })();
            {
              const o = (() => {
                return $f29681;
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
                  const $t29677 = s.x;
                  {
                    const $t29678 = s.y;
                    {
                      const $t29679 = o.radius;
                      return Canvas$arc(ctx, $t29677, $t29678, $t29679, 0., 6.28318530718);
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
const $jp29687$apply$3824$clo = { _0: ($_, $clo) => $jp29687$apply$3824($clo) };

function $jp29726$apply$3827($clo) {
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
          const $t29725 = (() => {
            {
              const $t29631_i9719 = (() => {
                {
                  const $t29630_i9718 = (() => {
                    {
                      const $t29629_i9717 = (() => {
                        {
                          const $t29626_i9714 = (() => {
                            {
                              const $t29625_i9713 = s.x;
                              return ($t29625_i9713 + 4.);
                            }
                          })();
                          {
                            const $t29628_i9716 = (() => {
                              {
                                const $t29627_i9715 = s.y;
                                return ($t29627_i9715 + 4.);
                              }
                            })();
                            {
                              const x_i12515 = (() => {
                                {
                                  const $t29500_i12514 = (() => {
                                    {
                                      const $t29499_i12513 = (() => {
                                        {
                                          const $t29497_i12511 = ($t29626_i9714 * 12.9898);
                                          {
                                            const $t29498_i12512 = ($t29628_i9716 * 78.233);
                                            return ($t29497_i12511 + $t29498_i12512);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29499_i12513);
                                    }
                                  })();
                                  return ($t29500_i12514 * 43758.5453);
                                }
                              })();
                              {
                                const $t29501_i12517 = (() => {
                                  {
                                    const $t1603_i5323_i12516 = Math.floor(x_i12515);
                                    return $t1603_i5323_i12516;
                                  }
                                })();
                                return (x_i12515 - $t29501_i12517);
                              }
                            }
                          }
                        }
                      })();
                      return ($t29629_i9717 * 4.);
                    }
                  })();
                  return Math.trunc($t29630_i9718);
                }
              })();
              return (2 + $t29631_i9719);
            }
          })();
          return draw_pulse_particle(ctx, s, t, $t29725, 0);
        }
      }
    }
  }
}
const $jp29726$apply$3827$clo = { _0: ($_, $clo) => $jp29726$apply$3827($clo) };

function $jp29728$apply$3828($clo) {
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
          const $t29725 = (() => {
            {
              const $t29631_i9727 = (() => {
                {
                  const $t29630_i9726 = (() => {
                    {
                      const $t29629_i9725 = (() => {
                        {
                          const $t29626_i9722 = (() => {
                            {
                              const $t29625_i9721 = s.x;
                              return ($t29625_i9721 + 4.);
                            }
                          })();
                          {
                            const $t29628_i9724 = (() => {
                              {
                                const $t29627_i9723 = s.y;
                                return ($t29627_i9723 + 4.);
                              }
                            })();
                            {
                              const x_i12524 = (() => {
                                {
                                  const $t29500_i12523 = (() => {
                                    {
                                      const $t29499_i12522 = (() => {
                                        {
                                          const $t29497_i12520 = ($t29626_i9722 * 12.9898);
                                          {
                                            const $t29498_i12521 = ($t29628_i9724 * 78.233);
                                            return ($t29497_i12520 + $t29498_i12521);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29499_i12522);
                                    }
                                  })();
                                  return ($t29500_i12523 * 43758.5453);
                                }
                              })();
                              {
                                const $t29501_i12526 = (() => {
                                  {
                                    const $t1603_i5323_i12525 = Math.floor(x_i12524);
                                    return $t1603_i5323_i12525;
                                  }
                                })();
                                return (x_i12524 - $t29501_i12526);
                              }
                            }
                          }
                        }
                      })();
                      return ($t29629_i9725 * 4.);
                    }
                  })();
                  return Math.trunc($t29630_i9726);
                }
              })();
              return (2 + $t29631_i9727);
            }
          })();
          return draw_pulse_particle(ctx, s, t, $t29725, 0);
        }
      }
    }
  }
}
const $jp29728$apply$3828$clo = { _0: ($_, $clo) => $jp29728$apply$3828($clo) };

function $jp29862$apply$3831($clo) {
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
const $jp29862$apply$3831$clo = { _0: ($_, $clo) => $jp29862$apply$3831($clo) };

function $lam30136$apply$3852($clo, k) {
  {
    const $t30137 = (() => {
      return (k === "m");
    })();
    {
      const $t30138 = (k === "M");
      return ($t30137 || $t30138);
    }
  }
}
const $lam30136$apply$3852$clo = { _0: ($_, $clo, k) => $lam30136$apply$3852($clo, k) };

function $jp30194$apply$3854($clo) {
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
const $jp30194$apply$3854$clo = { _0: ($_, $clo) => $jp30194$apply$3854($clo) };

function $lam30205$apply$3855($clo, _) {
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
const $lam30205$apply$3855$clo = { _0: ($_, $clo, _) => $lam30205$apply$3855($clo, _) };

function $lam30218$apply$3856($clo, _) {
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
const $lam30218$apply$3856$clo = { _0: ($_, $clo, _) => $lam30218$apply$3856($clo, _) };

function go$apply$4114($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$4114$clo = { _0: ($_, $clo, lst, acc) => go$apply$4114($clo, lst, acc) };

function go$apply$4341($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$4341$clo = { _0: ($_, $clo, lst, acc) => go$apply$4341($clo, lst, acc) };

function go$apply$4761($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10719 = { $: "$Clo_go$5268", _0: go$apply$5268 };
            {
              const $t274_i10720 = { $: "Nil" };
              return go$apply$5268(go_i10719, acc, $t274_i10720);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4763$clo = { _0: ($_, $clo, lst, acc) => go$apply$4763($clo, lst, acc) };

function go$apply$4765($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10724 = { $: "$Clo_go$5268", _0: go$apply$5268 };
            {
              const $t274_i10725 = { $: "Nil" };
              return go$apply$5268(go_i10724, acc, $t274_i10725);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10729 = { $: "$Clo_go$5270", _0: go$apply$5270 };
            {
              const $t274_i10730 = { $: "Nil" };
              return go$apply$5270(go_i10729, acc, $t274_i10730);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4767$clo = { _0: ($_, $clo, lst, acc) => go$apply$4767($clo, lst, acc) };

function go$apply$4769($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10734 = { $: "$Clo_go$5270", _0: go$apply$5270 };
            {
              const $t274_i10735 = { $: "Nil" };
              return go$apply$5270(go_i10734, acc, $t274_i10735);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
const go$apply$4769$clo = { _0: ($_, $clo, lst, acc) => go$apply$4769($clo, lst, acc) };

function go$apply$4771($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$4771$clo = { _0: ($_, $clo, lst, acc) => go$apply$4771($clo, lst, acc) };

function go$apply$4773($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f276 = lst._0;
        const $f277 = lst._1;
        {
          const t = $f277;
          {
            const h = $f276;
            {
              const $t275 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t275);
            }
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
const go$apply$4773$clo = { _0: ($_, $clo, lst, acc) => go$apply$4773($clo, lst, acc) };

function go$apply$4775($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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

function go$apply$4777($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10745 = { $: "$Clo_go$4775", _0: go$apply$4775 };
            {
              const $t274_i10746 = { $: "Nil" };
              return go$apply$4775(go_i10745, acc, $t274_i10746);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
const go$apply$4777$clo = { _0: ($_, $clo, lst, acc) => go$apply$4777($clo, lst, acc) };

function go$apply$4779($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10750 = { $: "$Clo_go$4775", _0: go$apply$4775 };
            {
              const $t274_i10751 = { $: "Nil" };
              return go$apply$4775(go_i10750, acc, $t274_i10751);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4779$clo = { _0: ($_, $clo, lst, acc) => go$apply$4779($clo, lst, acc) };

function go$apply$4781($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10755 = { $: "$Clo_go$4341", _0: go$apply$4341 };
            {
              const $t274_i10756 = { $: "Nil" };
              return go$apply$4341(go_i10755, acc, $t274_i10756);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
const go$apply$4781$clo = { _0: ($_, $clo, lst, acc) => go$apply$4781($clo, lst, acc) };

function go$apply$4783($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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
const go$apply$4783$clo = { _0: ($_, $clo, lst, acc) => go$apply$4783($clo, lst, acc) };

function go$apply$4786($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t567 = (() => {
              {
                const go_i10766 = { $: "$Clo_go$4771", _0: go$apply$4771 };
                {
                  const $t274_i10767 = { $: "Nil" };
                  return go$apply$4771(go_i10766, yes, $t274_i10767);
                }
              }
            })();
            {
              const $t568 = (() => {
                {
                  const go_i10763 = { $: "$Clo_go$4771", _0: go$apply$4771 };
                  {
                    const $t274_i10764 = { $: "Nil" };
                    return go$apply$4771(go_i10763, no, $t274_i10764);
                  }
                }
              })();
              return { _0: $t567, _1: $t568 };
            }
          }
          break;
        }
        case "Cons": {
          const $f572 = lst._0;
          const $f573 = lst._1;
          {
            const t = $f573;
            {
              const h = $f572;
              {
                const $t569 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t569 === true) {
                  return (() => {
                    {
                      const $t570 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t570, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t571 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t571);
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
const go$apply$4786$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4786($clo, lst, yes, no) };

function go$apply$4789($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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

function go$apply$4792($clo, lst, yes, no) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const $t567 = (() => {
              {
                const go_i10778 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                {
                  const $t274_i10779 = { $: "Nil" };
                  return go$apply$4775(go_i10778, yes, $t274_i10779);
                }
              }
            })();
            {
              const $t568 = (() => {
                {
                  const go_i10775 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                  {
                    const $t274_i10776 = { $: "Nil" };
                    return go$apply$4775(go_i10775, no, $t274_i10776);
                  }
                }
              })();
              return { _0: $t567, _1: $t568 };
            }
          }
          break;
        }
        case "Cons": {
          const $f572 = lst._0;
          const $f573 = lst._1;
          {
            const t = $f573;
            {
              const h = $f572;
              {
                const $t569 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t569 === true) {
                  return (() => {
                    {
                      const $t570 = { $: "Cons", _0: h, _1: yes };
                      return go._0(go, t, $t570, no);
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t571 = { $: "Cons", _0: h, _1: no };
                      return go._0(go, t, yes, $t571);
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
const go$apply$4792$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4792($clo, lst, yes, no) };

function $lam689$apply$4794($clo, y) {
  {
    const x = (() => {
      return $clo._1;
    })();
    return (y === x);
  }
}
const $lam689$apply$4794$clo = { _0: ($_, $clo, y) => $lam689$apply$4794($clo, y) };

function go$apply$4796($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f276 = lst._0;
        const $f277 = lst._1;
        {
          const t = $f277;
          {
            const h = $f276;
            {
              const $t275 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t275);
            }
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

function go$apply$4798($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10786 = { $: "$Clo_go$4771", _0: go$apply$4771 };
            {
              const $t274_i10787 = { $: "Nil" };
              return go$apply$4771(go_i10786, acc, $t274_i10787);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4798$clo = { _0: ($_, $clo, lst, acc) => go$apply$4798($clo, lst, acc) };

function go$apply$4801($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f276 = lst._0;
        const $f277 = lst._1;
        {
          const t = $f277;
          {
            const h = $f276;
            {
              const $t275 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t275);
            }
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
const go$apply$4801$clo = { _0: ($_, $clo, lst, acc) => go$apply$4801($clo, lst, acc) };

function go$apply$4804($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10798 = { $: "$Clo_go$5273", _0: go$apply$5273 };
            {
              const $t274_i10799 = { $: "Nil" };
              return go$apply$5273(go_i10798, acc, $t274_i10799);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10795 = { $: "$Clo_go$5273", _0: go$apply$5273 };
                {
                  const $t274_i10796 = { $: "Nil" };
                  return go$apply$5273(go_i10795, acc, $t274_i10796);
                }
              }
              break;
            }
            case "Cons": {
              const $f523 = lst._0;
              const $f524 = lst._1;
              {
                const t = $f524;
                {
                  const h = $f523;
                  {
                    const $t521 = (k - 1);
                    {
                      const $t522 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t521, $t522);
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
const go$apply$4804$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4804($clo, lst, k, acc) };

function go$apply$4806($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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

function go$apply$4810($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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
const go$apply$4810$clo = { _0: ($_, $clo, lst, acc) => go$apply$4810($clo, lst, acc) };

function go$apply$4813($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f276 = lst._0;
        const $f277 = lst._1;
        {
          const t = $f277;
          {
            const h = $f276;
            {
              const $t275 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t275);
            }
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
const go$apply$4813$clo = { _0: ($_, $clo, lst, acc) => go$apply$4813($clo, lst, acc) };

function go$apply$4815($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10815 = { $: "$Clo_go$4819", _0: go$apply$4819 };
            {
              const $t274_i10816 = { $: "Nil" };
              return go$apply$4819(go_i10815, acc, $t274_i10816);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10812 = { $: "$Clo_go$4819", _0: go$apply$4819 };
                {
                  const $t274_i10813 = { $: "Nil" };
                  return go$apply$4819(go_i10812, acc, $t274_i10813);
                }
              }
              break;
            }
            case "Cons": {
              const $f523 = lst._0;
              const $f524 = lst._1;
              {
                const t = $f524;
                {
                  const h = $f523;
                  {
                    const $t521 = (k - 1);
                    {
                      const $t522 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t521, $t522);
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
const go$apply$4815$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4815($clo, lst, k, acc) };

function go$apply$4817($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10820 = { $: "$Clo_go$4114", _0: go$apply$4114 };
            {
              const $t274_i10821 = { $: "Nil" };
              return go$apply$4114(go_i10820, acc, $t274_i10821);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$4819$clo = { _0: ($_, $clo, lst, acc) => go$apply$4819($clo, lst, acc) };

function go$apply$4821($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f276 = lst._0;
        const $f277 = lst._1;
        {
          const t = $f277;
          {
            const h = $f276;
            {
              const $t275 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t275);
            }
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
const go$apply$4821$clo = { _0: ($_, $clo, lst, acc) => go$apply$4821($clo, lst, acc) };

function go$apply$4823($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10829 = { $: "$Clo_go$5277", _0: go$apply$5277 };
            {
              const $t274_i10830 = { $: "Nil" };
              return go$apply$5277(go_i10829, acc, $t274_i10830);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4823$clo = { _0: ($_, $clo, lst, acc) => go$apply$4823($clo, lst, acc) };

function go$apply$4826($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10838 = { $: "$Clo_go$5277", _0: go$apply$5277 };
            {
              const $t274_i10839 = { $: "Nil" };
              return go$apply$5277(go_i10838, acc, $t274_i10839);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10835 = { $: "$Clo_go$5277", _0: go$apply$5277 };
                {
                  const $t274_i10836 = { $: "Nil" };
                  return go$apply$5277(go_i10835, acc, $t274_i10836);
                }
              }
              break;
            }
            case "Cons": {
              const $f523 = lst._0;
              const $f524 = lst._1;
              {
                const t = $f524;
                {
                  const h = $f523;
                  {
                    const $t521 = (k - 1);
                    {
                      const $t522 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t521, $t522);
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
const go$apply$4826$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4826($clo, lst, k, acc) };

function go$apply$4829($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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
const go$apply$4829$clo = { _0: ($_, $clo, lst, acc) => go$apply$4829($clo, lst, acc) };

function go$apply$4831($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const pred = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10846 = { $: "$Clo_go$5279", _0: go$apply$5279 };
            {
              const $t274_i10847 = { $: "Nil" };
              return go$apply$5279(go_i10846, acc, $t274_i10847);
            }
          }
          break;
        }
        case "Cons": {
          const $f317 = lst._0;
          const $f318 = lst._1;
          {
            const t = $f318;
            {
              const h = $f317;
              {
                const $t315 = (() => {
                  return pred._0(pred, h);
                })();
                if ($t315 === true) {
                  return (() => {
                    {
                      const $t316 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t316);
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
const go$apply$4831$clo = { _0: ($_, $clo, lst, acc) => go$apply$4831($clo, lst, acc) };

function go$apply$4833($clo, lst, acc) {
  {
    const go = (() => {
      return $clo;
    })();
    {
      const f = $clo._1;
      switch (lst.$) {
        case "Nil": {
          {
            const go_i10851 = { $: "$Clo_go$5279", _0: go$apply$5279 };
            {
              const $t274_i10852 = { $: "Nil" };
              return go$apply$5279(go_i10851, acc, $t274_i10852);
            }
          }
          break;
        }
        case "Cons": {
          const $f285 = lst._0;
          const $f286 = lst._1;
          {
            const t = $f286;
            {
              const h = $f285;
              {
                const $t283 = (() => {
                  return f._0(f, h);
                })();
                {
                  const $t284 = { $: "Cons", _0: $t283, _1: acc };
                  return go._0(go, t, $t284);
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
const go$apply$4833$clo = { _0: ($_, $clo, lst, acc) => go$apply$4833($clo, lst, acc) };

function go$apply$4835($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10859 = { $: "$Clo_go$4341", _0: go$apply$4341 };
            {
              const $t274_i10860 = { $: "Nil" };
              return go$apply$4341(go_i10859, acc, $t274_i10860);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10856 = { $: "$Clo_go$4341", _0: go$apply$4341 };
                {
                  const $t274_i10857 = { $: "Nil" };
                  return go$apply$4341(go_i10856, acc, $t274_i10857);
                }
              }
              break;
            }
            case "Cons": {
              const $f523 = lst._0;
              const $f524 = lst._1;
              {
                const t = $f524;
                {
                  const h = $f523;
                  {
                    const $t521 = (k - 1);
                    {
                      const $t522 = { $: "Cons", _0: h, _1: acc };
                      return go._0(go, t, $t521, $t522);
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
const go$apply$4835$clo = { _0: ($_, $clo, lst, k, acc) => go$apply$4835($clo, lst, k, acc) };

function go$apply$4837($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f261 = lst._0;
        const $f262 = lst._1;
        {
          const t = $f262;
          {
            const $t260 = (acc + 1);
            return go._0(go, t, $t260);
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
const go$apply$4837$clo = { _0: ($_, $clo, lst, acc) => go$apply$4837($clo, lst, acc) };

function go$apply$5268($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5268$clo = { _0: ($_, $clo, lst, acc) => go$apply$5268($clo, lst, acc) };

function go$apply$5270($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5270$clo = { _0: ($_, $clo, lst, acc) => go$apply$5270($clo, lst, acc) };

function go$apply$5273($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5273$clo = { _0: ($_, $clo, lst, acc) => go$apply$5273($clo, lst, acc) };

function go$apply$5275($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5275$clo = { _0: ($_, $clo, lst, acc) => go$apply$5275($clo, lst, acc) };

function go$apply$5277($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5277$clo = { _0: ($_, $clo, lst, acc) => go$apply$5277($clo, lst, acc) };

function go$apply$5279($clo, lst, acc) {
  {
    const go = $clo;
    switch (lst.$) {
      case "Nil": {
        return acc;
        break;
      }
      case "Cons": {
        const $f268 = lst._0;
        const $f269 = lst._1;
        {
          const t = $f269;
          {
            const h = $f268;
            {
              const $t267 = { $: "Cons", _0: h, _1: acc };
              return go._0(go, t, $t267);
            }
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
const go$apply$5279$clo = { _0: ($_, $clo, lst, acc) => go$apply$5279($clo, lst, acc) };

export { main };
main();
