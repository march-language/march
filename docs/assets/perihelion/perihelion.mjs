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
    const $t15824 = (k <= 0);
    if ($t15824 === true) {
      return rng;
    } else {
      return (() => {
        {
          const $p15826 = Random$next_raw(rng);
          {
            const r2 = $p15826._1;
            {
              const $t15825 = (k - 1);
              return Random$warmup(r2, $t15825);
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
          const $t15829 = (() => {
            {
              const $t15827 = (n - lo);
              return ($t15827 / 4294967296);
            }
          })();
          return march_int_and($t15829, 4294967295);
        }
      })();
      {
        const a = (() => {
          {
            const x$sh1_i1935 = (() => {
              {
                const $t15818_i1934 = (lo + 2654435769);
                return march_int_and($t15818_i1934, 4294967295);
              }
            })();
            {
              const x$sh2_i1938 = (() => {
                {
                  const $t15820_i1937 = (() => {
                    {
                      const $t15819_i1936 = march_int_shr(x$sh1_i1935, 16);
                      return march_int_xor(x$sh1_i1935, $t15819_i1936);
                    }
                  })();
                  {
                    const xh_i11898 = march_int_shr($t15820_i1937, 16);
                    {
                      const xl_i11899 = march_int_and($t15820_i1937, 65535);
                      {
                        const $t15809_i11904 = (() => {
                          {
                            const $t15807_i11902 = (() => {
                              {
                                const $t15806_i11901 = (() => {
                                  {
                                    const $t15805_i11900 = (xh_i11898 * 569420461);
                                    return march_int_and($t15805_i11900, 65535);
                                  }
                                })();
                                return ($t15806_i11901 * 65536);
                              }
                            })();
                            {
                              const $t15808_i11903 = (xl_i11899 * 569420461);
                              return ($t15807_i11902 + $t15808_i11903);
                            }
                          }
                        })();
                        return march_int_and($t15809_i11904, 4294967295);
                      }
                    }
                  }
                }
              })();
              {
                const x$sh3_i1941 = (() => {
                  {
                    const $t15822_i1940 = (() => {
                      {
                        const $t15821_i1939 = march_int_shr(x$sh2_i1938, 15);
                        return march_int_xor(x$sh2_i1938, $t15821_i1939);
                      }
                    })();
                    {
                      const xh_i11887 = march_int_shr($t15822_i1940, 16);
                      {
                        const xl_i11888 = march_int_and($t15822_i1940, 65535);
                        {
                          const $t15809_i11893 = (() => {
                            {
                              const $t15807_i11891 = (() => {
                                {
                                  const $t15806_i11890 = (() => {
                                    {
                                      const $t15805_i11889 = (xh_i11887 * 1935289751);
                                      return march_int_and($t15805_i11889, 65535);
                                    }
                                  })();
                                  return ($t15806_i11890 * 65536);
                                }
                              })();
                              {
                                const $t15808_i11892 = (xl_i11888 * 1935289751);
                                return ($t15807_i11891 + $t15808_i11892);
                              }
                            }
                          })();
                          return march_int_and($t15809_i11893, 4294967295);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t15823_i1942 = march_int_shr(x$sh3_i1941, 15);
                  return march_int_xor(x$sh3_i1941, $t15823_i1942);
                }
              }
            }
          }
        })();
        {
          const b = (() => {
            {
              const $t15830 = march_int_xor(hi, a);
              {
                const x$sh1_i1923 = (() => {
                  {
                    const $t15818_i1922 = ($t15830 + 2654435769);
                    return march_int_and($t15818_i1922, 4294967295);
                  }
                })();
                {
                  const x$sh2_i1926 = (() => {
                    {
                      const $t15820_i1925 = (() => {
                        {
                          const $t15819_i1924 = march_int_shr(x$sh1_i1923, 16);
                          return march_int_xor(x$sh1_i1923, $t15819_i1924);
                        }
                      })();
                      {
                        const xh_i11873 = march_int_shr($t15820_i1925, 16);
                        {
                          const xl_i11874 = march_int_and($t15820_i1925, 65535);
                          {
                            const $t15809_i11879 = (() => {
                              {
                                const $t15807_i11877 = (() => {
                                  {
                                    const $t15806_i11876 = (() => {
                                      {
                                        const $t15805_i11875 = (xh_i11873 * 569420461);
                                        return march_int_and($t15805_i11875, 65535);
                                      }
                                    })();
                                    return ($t15806_i11876 * 65536);
                                  }
                                })();
                                {
                                  const $t15808_i11878 = (xl_i11874 * 569420461);
                                  return ($t15807_i11877 + $t15808_i11878);
                                }
                              }
                            })();
                            return march_int_and($t15809_i11879, 4294967295);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const x$sh3_i1929 = (() => {
                      {
                        const $t15822_i1928 = (() => {
                          {
                            const $t15821_i1927 = march_int_shr(x$sh2_i1926, 15);
                            return march_int_xor(x$sh2_i1926, $t15821_i1927);
                          }
                        })();
                        {
                          const xh_i11862 = march_int_shr($t15822_i1928, 16);
                          {
                            const xl_i11863 = march_int_and($t15822_i1928, 65535);
                            {
                              const $t15809_i11868 = (() => {
                                {
                                  const $t15807_i11866 = (() => {
                                    {
                                      const $t15806_i11865 = (() => {
                                        {
                                          const $t15805_i11864 = (xh_i11862 * 1935289751);
                                          return march_int_and($t15805_i11864, 65535);
                                        }
                                      })();
                                      return ($t15806_i11865 * 65536);
                                    }
                                  })();
                                  {
                                    const $t15808_i11867 = (xl_i11863 * 1935289751);
                                    return ($t15807_i11866 + $t15808_i11867);
                                  }
                                }
                              })();
                              return march_int_and($t15809_i11868, 4294967295);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t15823_i1930 = march_int_shr(x$sh3_i1929, 15);
                      return march_int_xor(x$sh3_i1929, $t15823_i1930);
                    }
                  }
                }
              }
            }
          })();
          {
            const c = (() => {
              {
                const $t15831 = march_int_xor(lo, b);
                {
                  const x$sh1_i1911 = (() => {
                    {
                      const $t15818_i1910 = ($t15831 + 2654435769);
                      return march_int_and($t15818_i1910, 4294967295);
                    }
                  })();
                  {
                    const x$sh2_i1914 = (() => {
                      {
                        const $t15820_i1913 = (() => {
                          {
                            const $t15819_i1912 = march_int_shr(x$sh1_i1911, 16);
                            return march_int_xor(x$sh1_i1911, $t15819_i1912);
                          }
                        })();
                        {
                          const xh_i11848 = march_int_shr($t15820_i1913, 16);
                          {
                            const xl_i11849 = march_int_and($t15820_i1913, 65535);
                            {
                              const $t15809_i11854 = (() => {
                                {
                                  const $t15807_i11852 = (() => {
                                    {
                                      const $t15806_i11851 = (() => {
                                        {
                                          const $t15805_i11850 = (xh_i11848 * 569420461);
                                          return march_int_and($t15805_i11850, 65535);
                                        }
                                      })();
                                      return ($t15806_i11851 * 65536);
                                    }
                                  })();
                                  {
                                    const $t15808_i11853 = (xl_i11849 * 569420461);
                                    return ($t15807_i11852 + $t15808_i11853);
                                  }
                                }
                              })();
                              return march_int_and($t15809_i11854, 4294967295);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const x$sh3_i1917 = (() => {
                        {
                          const $t15822_i1916 = (() => {
                            {
                              const $t15821_i1915 = march_int_shr(x$sh2_i1914, 15);
                              return march_int_xor(x$sh2_i1914, $t15821_i1915);
                            }
                          })();
                          {
                            const xh_i11837 = march_int_shr($t15822_i1916, 16);
                            {
                              const xl_i11838 = march_int_and($t15822_i1916, 65535);
                              {
                                const $t15809_i11843 = (() => {
                                  {
                                    const $t15807_i11841 = (() => {
                                      {
                                        const $t15806_i11840 = (() => {
                                          {
                                            const $t15805_i11839 = (xh_i11837 * 1935289751);
                                            return march_int_and($t15805_i11839, 65535);
                                          }
                                        })();
                                        return ($t15806_i11840 * 65536);
                                      }
                                    })();
                                    {
                                      const $t15808_i11842 = (xl_i11838 * 1935289751);
                                      return ($t15807_i11841 + $t15808_i11842);
                                    }
                                  }
                                })();
                                return march_int_and($t15809_i11843, 4294967295);
                              }
                            }
                          }
                        }
                      })();
                      {
                        const $t15823_i1918 = march_int_shr(x$sh3_i1917, 15);
                        return march_int_xor(x$sh3_i1917, $t15823_i1918);
                      }
                    }
                  }
                }
              }
            })();
            {
              const $t15832 = ({ s0: a, s1: b, s2: c, s3: 1 });
              return Random$warmup($t15832, 12);
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
        const $t15837 = (() => {
          {
            const $t15835 = (() => {
              {
                const $t15833 = rng.s0;
                {
                  const $t15834 = rng.s1;
                  return ($t15833 + $t15834);
                }
              }
            })();
            {
              const $t15836 = rng.s3;
              return ($t15835 + $t15836);
            }
          }
        })();
        return march_int_and($t15837, 4294967295);
      }
    })();
    {
      const a = (() => {
        {
          const $t15838 = rng.s1;
          {
            const $t15840 = (() => {
              {
                const $t15839 = rng.s1;
                return march_int_shr($t15839, 9);
              }
            })();
            return march_int_xor($t15838, $t15840);
          }
        }
      })();
      {
        const b = (() => {
          {
            const $t15845 = (() => {
              {
                const $t15841 = rng.s2;
                {
                  const $t15844 = (() => {
                    {
                      const $t15843 = (() => {
                        {
                          const $t15842 = rng.s2;
                          return march_int_shl($t15842, 3);
                        }
                      })();
                      return march_int_and($t15843, 4294967295);
                    }
                  })();
                  return ($t15841 + $t15844);
                }
              }
            })();
            return march_int_and($t15845, 4294967295);
          }
        })();
        {
          const c = (() => {
            {
              const $t15848 = (() => {
                {
                  const $t15847 = (() => {
                    {
                      const $t15846 = rng.s2;
                      {
                        const keep_i1960 = (() => {
                          {
                            const $t15812_i1959 = march_int_shr(4294967295, 21);
                            return march_int_and($t15846, $t15812_i1959);
                          }
                        })();
                        {
                          const $t15813_i1961 = march_int_shl(keep_i1960, 21);
                          {
                            const $t15815_i1963 = march_int_shr($t15846, 11);
                            return march_int_or($t15813_i1961, $t15815_i1963);
                          }
                        }
                      }
                    }
                  })();
                  return ($t15847 + t);
                }
              })();
              return march_int_and($t15848, 4294967295);
            }
          })();
          {
            const $t15852 = (() => {
              {
                const $t15851 = (() => {
                  {
                    const $t15850 = (() => {
                      {
                        const $t15849 = rng.s3;
                        return ($t15849 + 1);
                      }
                    })();
                    return march_int_and($t15850, 4294967295);
                  }
                })();
                return ({ s0: a, s1: b, s2: c, s3: $t15851 });
              }
            })();
            return { _0: t, _1: $t15852 };
          }
        }
      }
    }
  }
}
const Random$next_raw$clo = { _0: ($_, rng) => Random$next_raw(rng) };

function Dom$find(id) {
  {
    const $rc_534 = dom_get_element_by_id$clo._0(dom_get_element_by_id$clo, id);
    return $rc_534;
  }
}
const Dom$find$clo = { _0: ($_, id) => Dom$find(id) };

function Dom$set_attr(el, name, val) {
  {
    const $rc_554 = dom_set_attribute$clo._0(dom_set_attribute$clo, el, name, val);
    return $rc_554;
  }
}
const Dom$set_attr$clo = { _0: ($_, el, name, val) => Dom$set_attr(el, name, val) };

function Dom$taps(el) {
  {
    const $rc_574 = dom_taps$clo._0(dom_taps$clo, el);
    return $rc_574;
  }
}
const Dom$taps$clo = { _0: ($_, el) => Dom$taps(el) };

function Dom$store_get(key) {
  {
    const $rc_575 = dom_store_get$clo._0(dom_store_get$clo, key);
    return $rc_575;
  }
}
const Dom$store_get$clo = { _0: ($_, key) => Dom$store_get(key) };

function Dom$store_set(key, val) {
  {
    const $rc_576 = dom_store_set$clo._0(dom_store_set$clo, key, val);
    return $rc_576;
  }
}
const Dom$store_set$clo = { _0: ($_, key, val) => Dom$store_set(key, val) };

function Dom$pointer_pos(el) {
  {
    const $rc_577 = dom_pointer_pos$clo._0(dom_pointer_pos$clo, el);
    return $rc_577;
  }
}
const Dom$pointer_pos$clo = { _0: ($_, el) => Dom$pointer_pos(el) };

function Dom$on_frame(cb) {
  return dom_request_animation_frame$clo._0(dom_request_animation_frame$clo, cb);
}
const Dom$on_frame$clo = { _0: ($_, cb) => Dom$on_frame(cb) };

function Canvas$get_context(node) {
  {
    const $rc_580 = canvas_get_context$clo._0(canvas_get_context$clo, node);
    return $rc_580;
  }
}
const Canvas$get_context$clo = { _0: ($_, node) => Canvas$get_context(node) };

function Canvas$save(ctx) {
  {
    const $rc_581 = canvas_save$clo._0(canvas_save$clo, ctx);
    return $rc_581;
  }
}
const Canvas$save$clo = { _0: ($_, ctx) => Canvas$save(ctx) };

function Canvas$restore(ctx) {
  {
    const $rc_582 = canvas_restore$clo._0(canvas_restore$clo, ctx);
    return $rc_582;
  }
}
const Canvas$restore$clo = { _0: ($_, ctx) => Canvas$restore(ctx) };

function Canvas$translate(ctx, x, y) {
  {
    const $rc_583 = canvas_translate$clo._0(canvas_translate$clo, ctx, x, y);
    return $rc_583;
  }
}
const Canvas$translate$clo = { _0: ($_, ctx, x, y) => Canvas$translate(ctx, x, y) };

function Canvas$rotate(ctx, angle) {
  {
    const $rc_584 = canvas_rotate$clo._0(canvas_rotate$clo, ctx, angle);
    return $rc_584;
  }
}
const Canvas$rotate$clo = { _0: ($_, ctx, angle) => Canvas$rotate(ctx, angle) };

function Canvas$set_fill_style(ctx, color) {
  {
    const $rc_586 = canvas_set_fill_style$clo._0(canvas_set_fill_style$clo, ctx, color);
    return $rc_586;
  }
}
const Canvas$set_fill_style$clo = { _0: ($_, ctx, color) => Canvas$set_fill_style(ctx, color) };

function Canvas$set_stroke_style(ctx, color) {
  {
    const $rc_587 = canvas_set_stroke_style$clo._0(canvas_set_stroke_style$clo, ctx, color);
    return $rc_587;
  }
}
const Canvas$set_stroke_style$clo = { _0: ($_, ctx, color) => Canvas$set_stroke_style(ctx, color) };

function Canvas$set_line_width(ctx, w) {
  {
    const $rc_588 = canvas_set_line_width$clo._0(canvas_set_line_width$clo, ctx, w);
    return $rc_588;
  }
}
const Canvas$set_line_width$clo = { _0: ($_, ctx, w) => Canvas$set_line_width(ctx, w) };

function Canvas$set_global_alpha(ctx, a) {
  {
    const $rc_589 = canvas_set_global_alpha$clo._0(canvas_set_global_alpha$clo, ctx, a);
    return $rc_589;
  }
}
const Canvas$set_global_alpha$clo = { _0: ($_, ctx, a) => Canvas$set_global_alpha(ctx, a) };

function Canvas$set_font(ctx, font) {
  {
    const $rc_590 = canvas_set_font$clo._0(canvas_set_font$clo, ctx, font);
    return $rc_590;
  }
}
const Canvas$set_font$clo = { _0: ($_, ctx, font) => Canvas$set_font(ctx, font) };

function Canvas$fill_rect(ctx, x, y, w, h) {
  {
    const $rc_592 = canvas_fill_rect$clo._0(canvas_fill_rect$clo, ctx, x, y, w, h);
    return $rc_592;
  }
}
const Canvas$fill_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$fill_rect(ctx, x, y, w, h) };

function Canvas$stroke_rect(ctx, x, y, w, h) {
  {
    const $rc_593 = canvas_stroke_rect$clo._0(canvas_stroke_rect$clo, ctx, x, y, w, h);
    return $rc_593;
  }
}
const Canvas$stroke_rect$clo = { _0: ($_, ctx, x, y, w, h) => Canvas$stroke_rect(ctx, x, y, w, h) };

function Canvas$begin_path(ctx) {
  {
    const $rc_594 = canvas_begin_path$clo._0(canvas_begin_path$clo, ctx);
    return $rc_594;
  }
}
const Canvas$begin_path$clo = { _0: ($_, ctx) => Canvas$begin_path(ctx) };

function Canvas$close_path(ctx) {
  {
    const $rc_595 = canvas_close_path$clo._0(canvas_close_path$clo, ctx);
    return $rc_595;
  }
}
const Canvas$close_path$clo = { _0: ($_, ctx) => Canvas$close_path(ctx) };

function Canvas$move_to(ctx, x, y) {
  {
    const $rc_596 = canvas_move_to$clo._0(canvas_move_to$clo, ctx, x, y);
    return $rc_596;
  }
}
const Canvas$move_to$clo = { _0: ($_, ctx, x, y) => Canvas$move_to(ctx, x, y) };

function Canvas$line_to(ctx, x, y) {
  {
    const $rc_597 = canvas_line_to$clo._0(canvas_line_to$clo, ctx, x, y);
    return $rc_597;
  }
}
const Canvas$line_to$clo = { _0: ($_, ctx, x, y) => Canvas$line_to(ctx, x, y) };

function Canvas$arc(ctx, x, y, radius, start_angle, end_angle) {
  {
    const $rc_598 = canvas_arc$clo._0(canvas_arc$clo, ctx, x, y, radius, start_angle, end_angle);
    return $rc_598;
  }
}
const Canvas$arc$clo = { _0: ($_, ctx, x, y, radius, start_angle, end_angle) => Canvas$arc(ctx, x, y, radius, start_angle, end_angle) };

function Canvas$fill(ctx) {
  {
    const $rc_601 = canvas_fill$clo._0(canvas_fill$clo, ctx);
    return $rc_601;
  }
}
const Canvas$fill$clo = { _0: ($_, ctx) => Canvas$fill(ctx) };

function Canvas$stroke(ctx) {
  {
    const $rc_602 = canvas_stroke$clo._0(canvas_stroke$clo, ctx);
    return $rc_602;
  }
}
const Canvas$stroke$clo = { _0: ($_, ctx) => Canvas$stroke(ctx) };

function Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) {
  {
    const $rc_603 = canvas_fill_noise_circle$clo._0(canvas_fill_noise_circle$clo, ctx, cx, cy, radius, alpha);
    return $rc_603;
  }
}
const Canvas$fill_noise_circle$clo = { _0: ($_, ctx, cx, cy, radius, alpha) => Canvas$fill_noise_circle(ctx, cx, cy, radius, alpha) };

function Canvas$fill_text(ctx, text, x, y) {
  {
    const $rc_604 = canvas_fill_text$clo._0(canvas_fill_text$clo, ctx, text, x, y);
    return $rc_604;
  }
}
const Canvas$fill_text$clo = { _0: ($_, ctx, text, x, y) => Canvas$fill_text(ctx, text, x, y) };

function Canvas$set_text_align(ctx, align) {
  {
    const $rc_606 = canvas_set_text_align$clo._0(canvas_set_text_align$clo, ctx, align);
    return $rc_606;
  }
}
const Canvas$set_text_align$clo = { _0: ($_, ctx, align) => Canvas$set_text_align(ctx, align) };

function Audio$resume(actx) {
  {
    const $rc_610 = audio_resume$clo._0(audio_resume$clo, actx);
    return $rc_610;
  }
}
const Audio$resume$clo = { _0: ($_, actx) => Audio$resume(actx) };

function Audio$beep(actx, freq, duration, wave) {
  {
    const $rc_611 = audio_beep$clo._0(audio_beep$clo, actx, freq, duration, wave);
    return $rc_611;
  }
}
const Audio$beep$clo = { _0: ($_, actx, freq, duration, wave) => Audio$beep(actx, freq, duration, wave) };

function Audio$sweep(actx, freq_from, freq_to, duration, wave) {
  {
    const $rc_612 = audio_sweep$clo._0(audio_sweep$clo, actx, freq_from, freq_to, duration, wave);
    return $rc_612;
  }
}
const Audio$sweep$clo = { _0: ($_, actx, freq_from, freq_to, duration, wave) => Audio$sweep(actx, freq_from, freq_to, duration, wave) };

function Audio$noise_burst(actx, duration, filter_freq) {
  {
    const $rc_613 = audio_noise_burst$clo._0(audio_noise_burst$clo, actx, duration, filter_freq);
    return $rc_613;
  }
}
const Audio$noise_burst$clo = { _0: ($_, actx, duration, filter_freq) => Audio$noise_burst(actx, duration, filter_freq) };

function Perihelion$Combat$starkiller_target_idx(game) {
  {
    const raw = (() => {
      {
        const $t27593 = (() => {
          {
            const $t27592 = game.current;
            return ($t27592 + 1);
          }
        })();
        {
          const $t27594 = game.starkiller_target_offset;
          return ($t27593 + $t27594);
        }
      }
    })();
    {
      const max_idx = (() => {
        {
          const $t27596 = (() => {
            {
              const $t27595 = game.stars;
              {
                const go_i4534 = { $: "$Clo_go$4747", _0: go$apply$4747 };
                return go$apply$4747(go_i4534, $t27595, 0);
              }
            }
          })();
          return ($t27596 - 1);
        }
      })();
      {
        const $t27597 = (raw > max_idx);
        if ($t27597 === true) {
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
        const $t27606 = game.spawn_timer;
        return ($t27606 - dt_s);
      }
    })();
    {
      const $t27607 = (t > 0.);
      if ($t27607 === true) {
        return ({ ...game, spawn_timer: t });
      } else {
        return (() => {
          {
            const $p27633 = (() => {
              {
                const $t27608 = game.rng;
                {
                  const $p29256_i5182_i11941 = (() => {
                    {
                      const $p15861_i12633 = (() => {
                        {
                          const $p15858_i1974_i12624 = Random$next_raw($t27608);
                          {
                            const hi_i1975_i12625 = $p15858_i1974_i12624._0;
                            {
                              const rng2_i1976_i12626 = $p15858_i1974_i12624._1;
                              {
                                const $p15857_i1977_i12627 = Random$next_raw(rng2_i1976_i12626);
                                {
                                  const lo_i1978_i12628 = $p15857_i1977_i12627._0;
                                  {
                                    const rng3_i1979_i12629 = $p15857_i1977_i12627._1;
                                    {
                                      const $t15856_i1983_i12632 = (() => {
                                        {
                                          const $t15855_i1982_i12631 = (() => {
                                            {
                                              const $t15853_i1980_i12630 = march_int_and(hi_i1975_i12625, 1048575);
                                              return ($t15853_i1980_i12630 * 4294967296);
                                            }
                                          })();
                                          return ($t15855_i1982_i12631 + lo_i1978_i12628);
                                        }
                                      })();
                                      return { _0: $t15856_i1983_i12632, _1: rng3_i1979_i12629 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i12634 = $p15861_i12633._0;
                        {
                          const rng2_i12635 = $p15861_i12633._1;
                          {
                            const $t15860_i12637 = (() => {
                              {
                                const $t15859_i12636 = bits_i12634;
                                return ($t15859_i12636 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15860_i12637, _1: rng2_i12635 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i5183_i11942 = $p29256_i5182_i11941._0;
                    {
                      const rng2_i5184_i11943 = $p29256_i5182_i11941._1;
                      {
                        const out_i5185_i11944 = { _0: rng2_i5184_i11943, _1: t_i5183_i11942 };
                        return out_i5185_i11944;
                      }
                    }
                  }
                }
              }
            })();
            {
              const r1 = $p27633._0;
              {
                const side_f = $p27633._1;
                {
                  const $p27632 = (() => {
                    {
                      const $p29256_i5182_i11936 = (() => {
                        {
                          const $p15861_i12618 = (() => {
                            {
                              const $p15858_i1974_i12609 = Random$next_raw(r1);
                              {
                                const hi_i1975_i12610 = $p15858_i1974_i12609._0;
                                {
                                  const rng2_i1976_i12611 = $p15858_i1974_i12609._1;
                                  {
                                    const $p15857_i1977_i12612 = Random$next_raw(rng2_i1976_i12611);
                                    {
                                      const lo_i1978_i12613 = $p15857_i1977_i12612._0;
                                      {
                                        const rng3_i1979_i12614 = $p15857_i1977_i12612._1;
                                        {
                                          const $t15856_i1983_i12617 = (() => {
                                            {
                                              const $t15855_i1982_i12616 = (() => {
                                                {
                                                  const $t15853_i1980_i12615 = march_int_and(hi_i1975_i12610, 1048575);
                                                  return ($t15853_i1980_i12615 * 4294967296);
                                                }
                                              })();
                                              return ($t15855_i1982_i12616 + lo_i1978_i12613);
                                            }
                                          })();
                                          return { _0: $t15856_i1983_i12617, _1: rng3_i1979_i12614 };
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const bits_i12619 = $p15861_i12618._0;
                            {
                              const rng2_i12620 = $p15861_i12618._1;
                              {
                                const $t15860_i12622 = (() => {
                                  {
                                    const $t15859_i12621 = bits_i12619;
                                    return ($t15859_i12621 / 4.50359962737e+15);
                                  }
                                })();
                                return { _0: $t15860_i12622, _1: rng2_i12620 };
                              }
                            }
                          }
                        }
                      })();
                      {
                        const t_i5183_i11937 = $p29256_i5182_i11936._0;
                        {
                          const rng2_i5184_i11938 = $p29256_i5182_i11936._1;
                          {
                            const out_i5185_i11939 = { _0: rng2_i5184_i11938, _1: t_i5183_i11937 };
                            return out_i5185_i11939;
                          }
                        }
                      }
                    }
                  })();
                  {
                    const r2 = $p27632._0;
                    {
                      const y_f = $p27632._1;
                      {
                        const $p27631 = (() => {
                          {
                            const $p29256_i5182_i11931 = (() => {
                              {
                                const $p15861_i12603 = (() => {
                                  {
                                    const $p15858_i1974_i12594 = Random$next_raw(r2);
                                    {
                                      const hi_i1975_i12595 = $p15858_i1974_i12594._0;
                                      {
                                        const rng2_i1976_i12596 = $p15858_i1974_i12594._1;
                                        {
                                          const $p15857_i1977_i12597 = Random$next_raw(rng2_i1976_i12596);
                                          {
                                            const lo_i1978_i12598 = $p15857_i1977_i12597._0;
                                            {
                                              const rng3_i1979_i12599 = $p15857_i1977_i12597._1;
                                              {
                                                const $t15856_i1983_i12602 = (() => {
                                                  {
                                                    const $t15855_i1982_i12601 = (() => {
                                                      {
                                                        const $t15853_i1980_i12600 = march_int_and(hi_i1975_i12595, 1048575);
                                                        return ($t15853_i1980_i12600 * 4294967296);
                                                      }
                                                    })();
                                                    return ($t15855_i1982_i12601 + lo_i1978_i12598);
                                                  }
                                                })();
                                                return { _0: $t15856_i1983_i12602, _1: rng3_i1979_i12599 };
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const bits_i12604 = $p15861_i12603._0;
                                  {
                                    const rng2_i12605 = $p15861_i12603._1;
                                    {
                                      const $t15860_i12607 = (() => {
                                        {
                                          const $t15859_i12606 = bits_i12604;
                                          return ($t15859_i12606 / 4.50359962737e+15);
                                        }
                                      })();
                                      return { _0: $t15860_i12607, _1: rng2_i12605 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const t_i5183_i11932 = $p29256_i5182_i11931._0;
                              {
                                const rng2_i5184_i11933 = $p29256_i5182_i11931._1;
                                {
                                  const out_i5185_i11934 = { _0: rng2_i5184_i11933, _1: t_i5183_i11932 };
                                  return out_i5185_i11934;
                                }
                              }
                            }
                          }
                        })();
                        {
                          const r3 = $p27631._0;
                          {
                            const ang_f = $p27631._1;
                            {
                              const $p27630 = (() => {
                                {
                                  const $p29256_i5182_i11926 = (() => {
                                    {
                                      const $p15861_i12588 = (() => {
                                        {
                                          const $p15858_i1974_i12579 = Random$next_raw(r3);
                                          {
                                            const hi_i1975_i12580 = $p15858_i1974_i12579._0;
                                            {
                                              const rng2_i1976_i12581 = $p15858_i1974_i12579._1;
                                              {
                                                const $p15857_i1977_i12582 = Random$next_raw(rng2_i1976_i12581);
                                                {
                                                  const lo_i1978_i12583 = $p15857_i1977_i12582._0;
                                                  {
                                                    const rng3_i1979_i12584 = $p15857_i1977_i12582._1;
                                                    {
                                                      const $t15856_i1983_i12587 = (() => {
                                                        {
                                                          const $t15855_i1982_i12586 = (() => {
                                                            {
                                                              const $t15853_i1980_i12585 = march_int_and(hi_i1975_i12580, 1048575);
                                                              return ($t15853_i1980_i12585 * 4294967296);
                                                            }
                                                          })();
                                                          return ($t15855_i1982_i12586 + lo_i1978_i12583);
                                                        }
                                                      })();
                                                      return { _0: $t15856_i1983_i12587, _1: rng3_i1979_i12584 };
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const bits_i12589 = $p15861_i12588._0;
                                        {
                                          const rng2_i12590 = $p15861_i12588._1;
                                          {
                                            const $t15860_i12592 = (() => {
                                              {
                                                const $t15859_i12591 = bits_i12589;
                                                return ($t15859_i12591 / 4.50359962737e+15);
                                              }
                                            })();
                                            return { _0: $t15860_i12592, _1: rng2_i12590 };
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const t_i5183_i11927 = $p29256_i5182_i11926._0;
                                    {
                                      const rng2_i5184_i11928 = $p29256_i5182_i11926._1;
                                      {
                                        const out_i5185_i11929 = { _0: rng2_i5184_i11928, _1: t_i5183_i11927 };
                                        return out_i5185_i11929;
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const r4 = $p27630._0;
                                {
                                  const next_f = $p27630._1;
                                  {
                                    const $p27629 = (() => {
                                      {
                                        const $p29256_i5182_i11921 = (() => {
                                          {
                                            const $p15861_i12573 = (() => {
                                              {
                                                const $p15858_i1974_i12564 = Random$next_raw(r4);
                                                {
                                                  const hi_i1975_i12565 = $p15858_i1974_i12564._0;
                                                  {
                                                    const rng2_i1976_i12566 = $p15858_i1974_i12564._1;
                                                    {
                                                      const $p15857_i1977_i12567 = Random$next_raw(rng2_i1976_i12566);
                                                      {
                                                        const lo_i1978_i12568 = $p15857_i1977_i12567._0;
                                                        {
                                                          const rng3_i1979_i12569 = $p15857_i1977_i12567._1;
                                                          {
                                                            const $t15856_i1983_i12572 = (() => {
                                                              {
                                                                const $t15855_i1982_i12571 = (() => {
                                                                  {
                                                                    const $t15853_i1980_i12570 = march_int_and(hi_i1975_i12565, 1048575);
                                                                    return ($t15853_i1980_i12570 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15855_i1982_i12571 + lo_i1978_i12568);
                                                              }
                                                            })();
                                                            return { _0: $t15856_i1983_i12572, _1: rng3_i1979_i12569 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i12574 = $p15861_i12573._0;
                                              {
                                                const rng2_i12575 = $p15861_i12573._1;
                                                {
                                                  const $t15860_i12577 = (() => {
                                                    {
                                                      const $t15859_i12576 = bits_i12574;
                                                      return ($t15859_i12576 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15860_i12577, _1: rng2_i12575 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i5183_i11922 = $p29256_i5182_i11921._0;
                                          {
                                            const rng2_i5184_i11923 = $p29256_i5182_i11921._1;
                                            {
                                              const out_i5185_i11924 = { _0: rng2_i5184_i11923, _1: t_i5183_i11922 };
                                              return out_i5185_i11924;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const r5 = $p27629._0;
                                      {
                                        const shape_f = $p27629._1;
                                        {
                                          const from_left = (side_f < 0.5);
                                          {
                                            let x;
                                            if (from_left === true) {
                                              x = (0. - 20.);
                                            } else {
                                              x = (() => {
                                                {
                                                  const $t27609 = game.view_w;
                                                  return ($t27609 + 20.);
                                                }
                                              })();
                                            }
                                            {
                                              const y = (() => {
                                                {
                                                  const $t27610 = game.camera_y;
                                                  {
                                                    const $t27612 = (() => {
                                                      {
                                                        const $t27611 = game.view_h;
                                                        return (y_f * $t27611);
                                                      }
                                                    })();
                                                    return ($t27610 + $t27612);
                                                  }
                                                }
                                              })();
                                              {
                                                const jitter = (() => {
                                                  {
                                                    const $t27613 = (ang_f - 0.5);
                                                    return ($t27613 * 1.0472);
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
                                                        const $t27615 = (dir_x * 90.);
                                                        {
                                                          const $t27616 = Math.cos(jitter);
                                                          return ($t27615 * $t27616);
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const vy = (() => {
                                                        {
                                                          const $t27618 = Math.sin(jitter);
                                                          return (90. * $t27618);
                                                        }
                                                      })();
                                                      {
                                                        const a = (() => {
                                                          {
                                                            const $t27620 = { $: "AsteroidDrifting" };
                                                            return ({ x: x, y: y, vx: vx, vy: vy, radius: 10., shape_seed: shape_f, mode: $t27620 });
                                                          }
                                                        })();
                                                        {
                                                          const $t27621 = game.asteroids;
                                                          {
                                                            const $t27622 = (() => {
                                                              return { $: "Cons", _0: a, _1: $t27621 };
                                                            })();
                                                            {
                                                              const $t27628 = (() => {
                                                                {
                                                                  const $t27627 = (() => {
                                                                    {
                                                                      const $t27625 = (() => {
                                                                        {
                                                                          const $t27624 = (next_f - 0.5);
                                                                          return ($t27624 * 2.);
                                                                        }
                                                                      })();
                                                                      return ($t27625 * 1.);
                                                                    }
                                                                  })();
                                                                  return (4. + $t27627);
                                                                }
                                                              })();
                                                              return ({ ...game, asteroids: $t27622, rng: r5, spawn_timer: $t27628 });
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
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
    const $t27645 = (() => {
      {
        const $t27642 = (() => {
          {
            const $t27636 = (() => {
              {
                const $t27635 = (() => {
                  {
                    const $t27634 = game.camera_y;
                    return ($t27634 - 100.);
                  }
                })();
                return (y > $t27635);
              }
            })();
            {
              const $t27641 = (() => {
                {
                  const $t27640 = (() => {
                    {
                      const $t27639 = (() => {
                        {
                          const $t27637 = game.camera_y;
                          {
                            const $t27638 = game.view_h;
                            return ($t27637 + $t27638);
                          }
                        }
                      })();
                      return ($t27639 + 100.);
                    }
                  })();
                  return (y < $t27640);
                }
              })();
              return ($t27636 && $t27641);
            }
          }
        })();
        {
          const $t27644 = (() => {
            {
              const $t27643 = (0. - 100.);
              return (x > $t27643);
            }
          })();
          return ($t27642 && $t27644);
        }
      }
    })();
    {
      const $t27648 = (() => {
        {
          const $t27647 = (() => {
            {
              const $t27646 = game.view_w;
              return ($t27646 + 100.);
            }
          })();
          return (x < $t27647);
        }
      })();
      return ($t27645 && $t27648);
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
      const $f27658 = asteroids._0;
      const $f27659 = asteroids._1;
      {
        const rest = (() => {
          return $f27659;
        })();
        {
          const a = (() => {
            return $f27658;
          })();
          {
            const dx = (() => {
              {
                const $t27649 = a.x;
                return ($t27649 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27650 = a.y;
                  return ($t27650 - y);
                }
              })();
              {
                const d2 = (() => {
                  {
                    const $t27651 = (dx * dx);
                    {
                      const $t27652 = (dy * dy);
                      return ($t27651 + $t27652);
                    }
                  }
                })();
                {
                  const $t27653 = (d2 < best_d2);
                  if ($t27653 === true) {
                    return (() => {
                      {
                        const $t27657 = (() => {
                          {
                            const $t27654 = a.x;
                            {
                              const $t27655 = a.y;
                              {
                                const $t27656 = { _0: $t27654, _1: $t27655 };
                                return { $: "Some", _0: $t27656 };
                              }
                            }
                          }
                        })();
                        return Perihelion$Combat$nearest_in_list_ast(x, y, rest, d2, $t27657);
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
      const $f27670 = ships._0;
      const $f27671 = ships._1;
      {
        const rest = (() => {
          return $f27671;
        })();
        {
          const sh = (() => {
            return $f27670;
          })();
          {
            const pos = (() => {
              {
                const pos_i4556 = (() => {
                  {
                    const $t27598_i4554 = sh.x;
                    {
                      const $t27599_i4555 = sh.y;
                      return { _0: $t27598_i4554, _1: $t27599_i4555 };
                    }
                  }
                })();
                return pos_i4556;
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
                          const $t27664 = (dx * dx);
                          {
                            const $t27665 = (dy * dy);
                            return ($t27664 + $t27665);
                          }
                        }
                      })();
                      {
                        const $t27666 = (d2 < best_d2);
                        if ($t27666 === true) {
                          return (() => {
                            {
                              const $t27668 = (() => {
                                {
                                  const $t27667 = { _0: sx, _1: sy };
                                  return { $: "Some", _0: $t27667 };
                                }
                              })();
                              return Perihelion$Combat$nearest_in_list_ship(x, y, rest, d2, $t27668);
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
    const $p27690 = (() => {
      {
        const $t27678 = (220. * 220.);
        {
          const $t27679 = { $: "None" };
          return Perihelion$Combat$nearest_in_list_ast(x, y, asteroids, $t27678, $t27679);
        }
      }
    })();
    {
      const d2a = $p27690._0;
      {
        const besta = $p27690._1;
        {
          const $p27689 = (() => {
            return Perihelion$Combat$nearest_in_list_ship(x, y, ships, d2a, besta);
          })();
          {
            const bests = $p27689._1;
            switch (bests.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f27688 = bests._0;
                {
                  const pair = (() => {
                    return $f27688;
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
                                const $t27682 = (() => {
                                  {
                                    const $t27680 = (dx * dx);
                                    {
                                      const $t27681 = (dy * dy);
                                      return ($t27680 + $t27681);
                                    }
                                  }
                                })();
                                return Math.sqrt($t27682);
                              }
                            })();
                            {
                              const $t27683 = (d > 0.);
                              if ($t27683 === true) {
                                return (() => {
                                  {
                                    const $t27684 = (dx / d);
                                    {
                                      const $t27685 = (dy / d);
                                      {
                                        const $t27686 = { _0: $t27684, _1: $t27685 };
                                        return { $: "Some", _0: $t27686 };
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
        const $t27694 = (() => {
          {
            const $t27691 = s.x;
            {
              const $t27693 = (() => {
                {
                  const $t27692 = s.vx;
                  return ($t27692 * dt_s);
                }
              })();
              return ($t27691 + $t27693);
            }
          }
        })();
        {
          const $t27698 = (() => {
            {
              const $t27695 = s.y;
              {
                const $t27697 = (() => {
                  {
                    const $t27696 = s.vy;
                    return ($t27696 * dt_s);
                  }
                })();
                return ($t27695 + $t27697);
              }
            }
          })();
          {
            const $t27700 = (() => {
              {
                const $t27699 = s.ttl;
                return ($t27699 - dt_s);
              }
            })();
            return ({ ...s, x: $t27694, y: $t27698, ttl: $t27700 });
          }
        }
      }
    })();
    {
      const $t27702 = (() => {
        {
          const $t27701 = s.homing;
          return (!$t27701);
        }
      })();
      if ($t27702 === true) {
        return moved;
      } else {
        return (() => {
          {
            const $t27705 = (() => {
              {
                const $t27703 = s.x;
                {
                  const $t27704 = s.y;
                  return Perihelion$Combat$nearest_hazard_dir($t27703, $t27704, asteroids, ships);
                }
              }
            })();
            switch ($t27705.$) {
              case "None": {
                return moved;
                break;
              }
              case "Some": {
                const $f27731 = $t27705._0;
                {
                  const pair = $f27731;
                  {
                    const tx = pair._0;
                    {
                      const ty = pair._1;
                      {
                        const speed = (() => {
                          {
                            const $t27712 = (() => {
                              {
                                const $t27708 = (() => {
                                  {
                                    const $t27706 = s.vx;
                                    {
                                      const $t27707 = s.vx;
                                      return ($t27706 * $t27707);
                                    }
                                  }
                                })();
                                {
                                  const $t27711 = (() => {
                                    {
                                      const $t27709 = s.vy;
                                      {
                                        const $t27710 = s.vy;
                                        return ($t27709 * $t27710);
                                      }
                                    }
                                  })();
                                  return ($t27708 + $t27711);
                                }
                              }
                            })();
                            return Math.sqrt($t27712);
                          }
                        })();
                        {
                          const cur_ax = (() => {
                            {
                              const $t27713 = s.vx;
                              return ($t27713 / speed);
                            }
                          })();
                          {
                            const cur_ay = (() => {
                              {
                                const $t27714 = s.vy;
                                return ($t27714 / speed);
                              }
                            })();
                            {
                              const turned_ax = (() => {
                                {
                                  const $t27718 = (() => {
                                    {
                                      const $t27717 = (() => {
                                        {
                                          const $t27715 = (tx - cur_ax);
                                          return ($t27715 * 3.);
                                        }
                                      })();
                                      return ($t27717 * dt_s);
                                    }
                                  })();
                                  return (cur_ax + $t27718);
                                }
                              })();
                              {
                                const turned_ay = (() => {
                                  {
                                    const $t27722 = (() => {
                                      {
                                        const $t27721 = (() => {
                                          {
                                            const $t27719 = (ty - cur_ay);
                                            return ($t27719 * 3.);
                                          }
                                        })();
                                        return ($t27721 * dt_s);
                                      }
                                    })();
                                    return (cur_ay + $t27722);
                                  }
                                })();
                                {
                                  const norm = (() => {
                                    {
                                      const $t27725 = (() => {
                                        {
                                          const $t27723 = (turned_ax * turned_ax);
                                          {
                                            const $t27724 = (turned_ay * turned_ay);
                                            return ($t27723 + $t27724);
                                          }
                                        }
                                      })();
                                      return Math.sqrt($t27725);
                                    }
                                  })();
                                  {
                                    const $t27727 = (() => {
                                      {
                                        const $t27726 = (turned_ax / norm);
                                        return ($t27726 * speed);
                                      }
                                    })();
                                    {
                                      const $t27729 = (() => {
                                        {
                                          const $t27728 = (turned_ay / norm);
                                          return ($t27728 * speed);
                                        }
                                      })();
                                      return ({ ...moved, vx: $t27727, vy: $t27729 });
                                    }
                                  }
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
      const $t27732 = g1.player_shots;
      {
        const $t27736 = { $: "$Clo_$lam27733$3695", _0: $lam27733$apply$3695, _1: dt_s, _2: g1 };
        {
          const $t27737 = (() => {
            {
              const f_i4583 = $t27736;
              {
                const go_i4584 = { $: "$Clo_go$4755", _0: go$apply$4755, _1: f_i4583 };
                {
                  const $t291_i4585 = { $: "Nil" };
                  return go$apply$4755(go_i4584, $t27732, $t291_i4585);
                }
              }
            }
          })();
          {
            const $t27744 = { $: "$Clo_$lam27738$3696", _0: $lam27738$apply$3696, _1: g1 };
            {
              const p_shots = (() => {
                {
                  const pred_i4579 = $t27744;
                  {
                    const go_i4580 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4579 };
                    {
                      const $t323_i4581 = { $: "Nil" };
                      return go$apply$4753(go_i4580, $t27737, $t323_i4581);
                    }
                  }
                }
              })();
              {
                const $t27745 = g1.enemy_shots;
                {
                  const $t27749 = { $: "$Clo_$lam27746$3697", _0: $lam27746$apply$3697, _1: dt_s, _2: g1 };
                  {
                    const $t27750 = (() => {
                      {
                        const f_i4575 = $t27749;
                        {
                          const go_i4576 = { $: "$Clo_go$4755", _0: go$apply$4755, _1: f_i4575 };
                          {
                            const $t291_i4577 = { $: "Nil" };
                            return go$apply$4755(go_i4576, $t27745, $t291_i4577);
                          }
                        }
                      }
                    })();
                    {
                      const $t27757 = { $: "$Clo_$lam27751$3698", _0: $lam27751$apply$3698, _1: g1 };
                      {
                        const e_shots = (() => {
                          {
                            const pred_i4571 = $t27757;
                            {
                              const go_i4572 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4571 };
                              {
                                const $t323_i4573 = { $: "Nil" };
                                return go$apply$4753(go_i4572, $t27750, $t323_i4573);
                              }
                            }
                          }
                        })();
                        {
                          const $t27758 = g1.pickups;
                          {
                            const $t27762 = { $: "$Clo_$lam27759$3699", _0: $lam27759$apply$3699, _1: dt_s };
                            {
                              const $t27763 = (() => {
                                {
                                  const f_i4567 = $t27762;
                                  {
                                    const go_i4568 = { $: "$Clo_go$4751", _0: go$apply$4751, _1: f_i4567 };
                                    {
                                      const $t291_i4569 = { $: "Nil" };
                                      return go$apply$4751(go_i4568, $t27758, $t291_i4569);
                                    }
                                  }
                                }
                              })();
                              {
                                const $t27766 = { $: "$Clo_$lam27764$3700", _0: $lam27764$apply$3700 };
                                {
                                  const pickups = (() => {
                                    {
                                      const pred_i4563 = $t27766;
                                      {
                                        const go_i4564 = { $: "$Clo_go$4749", _0: go$apply$4749, _1: pred_i4563 };
                                        {
                                          const $t323_i4565 = { $: "Nil" };
                                          return go$apply$4749(go_i4564, $t27763, $t323_i4565);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27770 = (() => {
                                      {
                                        const $t27768 = (() => {
                                          {
                                            const $t27767 = g1.fire_cooldown;
                                            return ($t27767 > 0.);
                                          }
                                        })();
                                        if ($t27768 === true) {
                                          return (() => {
                                            {
                                              const $t27769 = g1.fire_cooldown;
                                              return ($t27769 - dt_s);
                                            }
                                          })();
                                        } else {
                                          return 0.;
                                        }
                                      }
                                    })();
                                    {
                                      const $t27774 = (() => {
                                        {
                                          const $t27772 = (() => {
                                            {
                                              const $t27771 = g1.starkiller_cooldown;
                                              return ($t27771 > 0.);
                                            }
                                          })();
                                          if ($t27772 === true) {
                                            return (() => {
                                              {
                                                const $t27773 = g1.starkiller_cooldown;
                                                return ($t27773 - dt_s);
                                              }
                                            })();
                                          } else {
                                            return 0.;
                                          }
                                        }
                                      })();
                                      return ({ ...g1, player_shots: p_shots, enemy_shots: e_shots, pickups: pickups, fire_cooldown: $t27770, starkiller_cooldown: $t27774 });
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
      const $f27781 = stars._0;
      const $f27782 = stars._1;
      {
        const rest = $f27782;
        {
          const s = $f27781;
          {
            const dx = (() => {
              {
                const $t27775 = s.x;
                return ($t27775 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27776 = s.y;
                  return ($t27776 - y);
                }
              })();
              {
                const d = (() => {
                  {
                    const $t27777 = (dx * dx);
                    {
                      const $t27778 = (dy * dy);
                      return ($t27777 + $t27778);
                    }
                  }
                })();
                {
                  const $t27779 = (d < best_d);
                  if ($t27779 === true) {
                    return (() => {
                      {
                        const $t27780 = { $: "Some", _0: s };
                        return Perihelion$Combat$nearest_star_for_asteroid(x, y, rest, $t27780, d);
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
    const $t27789 = (() => {
      {
        const $t27787 = { $: "None" };
        {
          const $t27788 = (240. * 240.);
          return Perihelion$Combat$nearest_star_for_asteroid(x, y, stars, $t27787, $t27788);
        }
      }
    })();
    switch ($t27789.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f27815 = $t27789._0;
        {
          const s = $f27815;
          {
            const dx = (() => {
              {
                const $t27790 = s.x;
                return ($t27790 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27791 = s.y;
                  return ($t27791 - y);
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t27794 = (() => {
                      {
                        const $t27792 = (dx * dx);
                        {
                          const $t27793 = (dy * dy);
                          return ($t27792 + $t27793);
                        }
                      }
                    })();
                    return Math.sqrt($t27794);
                  }
                })();
                {
                  const $t27795 = (dist > 0.);
                  if ($t27795 === true) {
                    return (() => {
                      {
                        const speed = (() => {
                          {
                            const $t27798 = (() => {
                              {
                                const $t27796 = (vx * vx);
                                {
                                  const $t27797 = (vy * vy);
                                  return ($t27796 + $t27797);
                                }
                              }
                            })();
                            return Math.sqrt($t27798);
                          }
                        })();
                        {
                          const nvx = (() => {
                            {
                              const $t27802 = (() => {
                                {
                                  const $t27801 = (() => {
                                    {
                                      const $t27799 = (dx / dist);
                                      return ($t27799 * 500.);
                                    }
                                  })();
                                  return ($t27801 * dt_s);
                                }
                              })();
                              return (vx + $t27802);
                            }
                          })();
                          {
                            const nvy = (() => {
                              {
                                const $t27806 = (() => {
                                  {
                                    const $t27805 = (() => {
                                      {
                                        const $t27803 = (dy / dist);
                                        return ($t27803 * 500.);
                                      }
                                    })();
                                    return ($t27805 * dt_s);
                                  }
                                })();
                                return (vy + $t27806);
                              }
                            })();
                            {
                              const nspeed = (() => {
                                {
                                  const $t27809 = (() => {
                                    {
                                      const $t27807 = (nvx * nvx);
                                      {
                                        const $t27808 = (nvy * nvy);
                                        return ($t27807 + $t27808);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t27809);
                                }
                              })();
                              {
                                const $t27810 = (nspeed > 0.);
                                if ($t27810 === true) {
                                  return (() => {
                                    {
                                      const $t27812 = (() => {
                                        {
                                          const $t27811 = (nvx / nspeed);
                                          return ($t27811 * speed);
                                        }
                                      })();
                                      {
                                        const $t27814 = (() => {
                                          {
                                            const $t27813 = (nvy / nspeed);
                                            return ($t27813 * speed);
                                          }
                                        })();
                                        return { _0: $t27812, _1: $t27814 };
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
        const $t27816 = (() => {
          {
            const go_i4593 = { $: "$Clo_go$4757", _0: go$apply$4757 };
            {
              const $t274_i4594 = { $: "Nil" };
              return go$apply$4757(go_i4593, acc, $t274_i4594);
            }
          }
        })();
        return ({ ...game, asteroids: $t27816 });
      }
      break;
    }
    case "Cons": {
      const $f27880 = asteroids._0;
      const $f27881 = asteroids._1;
      {
        const rest = $f27881;
        {
          const a = $f27880;
          {
            const $t27817 = a.mode;
            switch ($t27817.$) {
              case "AsteroidOrbiting": {
                const $f27874 = $t27817._0;
                const $f27875 = $t27817._1;
                {
                  const angle = (() => {
                    return $f27875;
                  })();
                  {
                    const idx = (() => {
                      return $f27874;
                    })();
                    {
                      const $t27818 = Perihelion$Core$star_at(game, idx);
                      switch ($t27818.$) {
                        case "None": {
                          return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                          break;
                        }
                        case "Some": {
                          const $f27833 = $t27818._0;
                          {
                            const s = $f27833;
                            {
                              const angle2 = (() => {
                                {
                                  const $t27820 = (1. * dt_s);
                                  return (angle + $t27820);
                                }
                              })();
                              {
                                const r = (() => {
                                  {
                                    const $t27821 = s.capture_radius;
                                    return ($t27821 * 0.8);
                                  }
                                })();
                                {
                                  const a2 = (() => {
                                    {
                                      const $t27826 = (() => {
                                        {
                                          const $t27823 = s.x;
                                          {
                                            const $t27825 = (() => {
                                              {
                                                const $t27824 = Math.cos(angle2);
                                                return ($t27824 * r);
                                              }
                                            })();
                                            return ($t27823 + $t27825);
                                          }
                                        }
                                      })();
                                      {
                                        const $t27830 = (() => {
                                          {
                                            const $t27827 = s.y;
                                            {
                                              const $t27829 = (() => {
                                                {
                                                  const $t27828 = Math.sin(angle2);
                                                  return ($t27828 * r);
                                                }
                                              })();
                                              return ($t27827 + $t27829);
                                            }
                                          }
                                        })();
                                        {
                                          const $t27831 = { $: "AsteroidOrbiting", _0: idx, _1: angle2 };
                                          return ({ ...a, x: $t27826, y: $t27830, mode: $t27831 });
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t27832 = { $: "Cons", _0: a2, _1: acc };
                                    return Perihelion$Combat$step_asteroids_go(game, rest, $t27832, dt_s);
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
                      const $t27834 = a.x;
                      {
                        const $t27835 = a.y;
                        {
                          const $t27836 = a.vx;
                          {
                            const $t27837 = a.vy;
                            {
                              const $t27838 = game.stars;
                              return Perihelion$Combat$arc_velocity($t27834, $t27835, $t27836, $t27837, $t27838, dt_s);
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
                            const $t27839 = a.x;
                            {
                              const $t27840 = (vx2 * dt_s);
                              return ($t27839 + $t27840);
                            }
                          }
                        })();
                        {
                          const y2 = (() => {
                            {
                              const $t27841 = a.y;
                              {
                                const $t27842 = (vy2 * dt_s);
                                return ($t27841 + $t27842);
                              }
                            }
                          })();
                          {
                            const $t27844 = (() => {
                              {
                                const $t27843 = Perihelion$Combat$in_band(game, x2, y2);
                                return (!$t27843);
                              }
                            })();
                            if ($t27844 === true) {
                              return Perihelion$Combat$step_asteroids_go(game, rest, acc, dt_s);
                            } else {
                              return (() => {
                                {
                                  const $t27846 = (() => {
                                    {
                                      const $t27845 = game.stars;
                                      return Perihelion$Combat$arrived_star($t27845, x2, y2, 0);
                                    }
                                  })();
                                  switch ($t27846.$) {
                                    case "None": {
                                      {
                                        const a2 = ({ ...a, x: x2, y: y2, vx: vx2, vy: vy2 });
                                        {
                                          const $t27847 = { $: "Cons", _0: a2, _1: acc };
                                          return Perihelion$Combat$step_asteroids_go(game, rest, $t27847, dt_s);
                                        }
                                      }
                                      break;
                                    }
                                    case "Some": {
                                      const $f27872 = $t27846._0;
                                      {
                                        const pair = $f27872;
                                        {
                                          const idx = pair._0;
                                          {
                                            const s = pair._1;
                                            {
                                              const $p27870 = (() => {
                                                {
                                                  const $t27848 = game.rng;
                                                  {
                                                    const $p29256_i5182_i11946 = (() => {
                                                      {
                                                        const $p15861_i12648 = (() => {
                                                          {
                                                            const $p15858_i1974_i12639 = Random$next_raw($t27848);
                                                            {
                                                              const hi_i1975_i12640 = $p15858_i1974_i12639._0;
                                                              {
                                                                const rng2_i1976_i12641 = $p15858_i1974_i12639._1;
                                                                {
                                                                  const $p15857_i1977_i12642 = Random$next_raw(rng2_i1976_i12641);
                                                                  {
                                                                    const lo_i1978_i12643 = $p15857_i1977_i12642._0;
                                                                    {
                                                                      const rng3_i1979_i12644 = $p15857_i1977_i12642._1;
                                                                      {
                                                                        const $t15856_i1983_i12647 = (() => {
                                                                          {
                                                                            const $t15855_i1982_i12646 = (() => {
                                                                              {
                                                                                const $t15853_i1980_i12645 = march_int_and(hi_i1975_i12640, 1048575);
                                                                                return ($t15853_i1980_i12645 * 4294967296);
                                                                              }
                                                                            })();
                                                                            return ($t15855_i1982_i12646 + lo_i1978_i12643);
                                                                          }
                                                                        })();
                                                                        return { _0: $t15856_i1983_i12647, _1: rng3_i1979_i12644 };
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const bits_i12649 = $p15861_i12648._0;
                                                          {
                                                            const rng2_i12650 = $p15861_i12648._1;
                                                            {
                                                              const $t15860_i12652 = (() => {
                                                                {
                                                                  const $t15859_i12651 = bits_i12649;
                                                                  return ($t15859_i12651 / 4.50359962737e+15);
                                                                }
                                                              })();
                                                              return { _0: $t15860_i12652, _1: rng2_i12650 };
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const t_i5183_i11947 = $p29256_i5182_i11946._0;
                                                      {
                                                        const rng2_i5184_i11948 = $p29256_i5182_i11946._1;
                                                        {
                                                          const out_i5185_i11949 = { _0: rng2_i5184_i11948, _1: t_i5183_i11947 };
                                                          return out_i5185_i11949;
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const rng2 = $p27870._0;
                                                {
                                                  const roll = $p27870._1;
                                                  {
                                                    const $t27850 = (roll < 0.35);
                                                    if ($t27850 === true) {
                                                      return (() => {
                                                        {
                                                          const angle = (() => {
                                                            {
                                                              const $t27852 = (() => {
                                                                {
                                                                  const $t27851 = s.y;
                                                                  return (y2 - $t27851);
                                                                }
                                                              })();
                                                              {
                                                                const $t27854 = (() => {
                                                                  {
                                                                    const $t27853 = s.x;
                                                                    return (x2 - $t27853);
                                                                  }
                                                                })();
                                                                return Math.atan2($t27852, $t27854);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const r = (() => {
                                                              {
                                                                const $t27855 = s.capture_radius;
                                                                return ($t27855 * 0.8);
                                                              }
                                                            })();
                                                            {
                                                              const a2 = (() => {
                                                                {
                                                                  const $t27860 = (() => {
                                                                    {
                                                                      const $t27857 = s.x;
                                                                      {
                                                                        const $t27859 = (() => {
                                                                          {
                                                                            const $t27858 = Math.cos(angle);
                                                                            return ($t27858 * r);
                                                                          }
                                                                        })();
                                                                        return ($t27857 + $t27859);
                                                                      }
                                                                    }
                                                                  })();
                                                                  {
                                                                    const $t27864 = (() => {
                                                                      {
                                                                        const $t27861 = s.y;
                                                                        {
                                                                          const $t27863 = (() => {
                                                                            {
                                                                              const $t27862 = Math.sin(angle);
                                                                              return ($t27862 * r);
                                                                            }
                                                                          })();
                                                                          return ($t27861 + $t27863);
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t27865 = { $: "AsteroidOrbiting", _0: idx, _1: angle };
                                                                      return ({ ...a, x: $t27860, y: $t27864, mode: $t27865 });
                                                                    }
                                                                  }
                                                                }
                                                              })();
                                                              {
                                                                const $t27866 = ({ ...game, rng: rng2 });
                                                                {
                                                                  const $t27867 = { $: "Cons", _0: a2, _1: acc };
                                                                  return Perihelion$Combat$step_asteroids_go($t27866, rest, $t27867, dt_s);
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
                                                            const $t27868 = ({ ...game, rng: rng2 });
                                                            {
                                                              const $t27869 = { $: "Cons", _0: a2, _1: acc };
                                                              return Perihelion$Combat$step_asteroids_go($t27868, rest, $t27869, dt_s);
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
    const $t27886 = game.asteroids;
    {
      const $t27887 = { $: "Nil" };
      return Perihelion$Combat$step_asteroids_go(game, $t27886, $t27887, dt_s);
    }
  }
}
const Perihelion$Combat$step_asteroids$clo = { _0: ($_, game, dt_s) => Perihelion$Combat$step_asteroids(game, dt_s) };

function Perihelion$Combat$step_ships(game, dt_s) {
  {
    const $t27888 = game.ships;
    {
      const $t27889 = { $: "Nil" };
      {
        const $t27890 = { $: "Nil" };
        return Perihelion$Combat$step_ships_go(game, $t27888, $t27889, $t27890, dt_s);
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
      const $f27901 = stars._0;
      const $f27902 = stars._1;
      {
        const rest = (() => {
          return $f27902;
        })();
        {
          const s = (() => {
            return $f27901;
          })();
          {
            const $t27891 = (i === skip_idx);
            if ($t27891 === true) {
              return (() => {
                {
                  const $t27892 = (i + 1);
                  return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $t27892, best, best_d);
                }
              })();
            } else {
              return (() => {
                {
                  const dx = (() => {
                    {
                      const $t27893 = s.x;
                      return ($t27893 - from_x);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t27894 = s.y;
                        return ($t27894 - from_y);
                      }
                    })();
                    {
                      const d = (() => {
                        {
                          const $t27895 = (dx * dx);
                          {
                            const $t27896 = (dy * dy);
                            return ($t27895 + $t27896);
                          }
                        }
                      })();
                      {
                        const $t27897 = (d < best_d);
                        {
                          const $jp1027_$t27898 = (i + 1);
                          if ($t27897 === true) {
                            return (() => {
                              {
                                const $t27899 = { $: "Some", _0: i };
                                return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp1027_$t27898, $t27899, d);
                              }
                            })();
                          } else {
                            return (() => {
                              return Perihelion$Combat$nearest_other_star(from_x, from_y, skip_idx, rest, $jp1027_$t27898, best, best_d);
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
      const $f27917 = stars._0;
      const $f27918 = stars._1;
      {
        const rest = $f27918;
        {
          const s = $f27917;
          {
            const dx = (() => {
              {
                const $t27907 = s.x;
                return ($t27907 - x);
              }
            })();
            {
              const dy = (() => {
                {
                  const $t27908 = s.y;
                  return ($t27908 - y);
                }
              })();
              {
                const $t27914 = (() => {
                  {
                    const $t27912 = (() => {
                      {
                        const $t27911 = (() => {
                          {
                            const $t27909 = (dx * dx);
                            {
                              const $t27910 = (dy * dy);
                              return ($t27909 + $t27910);
                            }
                          }
                        })();
                        return Math.sqrt($t27911);
                      }
                    })();
                    {
                      const $t27913 = s.capture_radius;
                      return ($t27912 <= $t27913);
                    }
                  }
                })();
                if ($t27914 === true) {
                  return (() => {
                    {
                      const $t27915 = { _0: i, _1: s };
                      return { $: "Some", _0: $t27915 };
                    }
                  })();
                } else {
                  return (() => {
                    {
                      const $t27916 = (i + 1);
                      return Perihelion$Combat$arrived_star(rest, x, y, $t27916);
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
        const $t27923 = game.ball_x;
        return ($t27923 - sx);
      }
    })();
    {
      const dy = (() => {
        {
          const $t27924 = game.ball_y;
          return ($t27924 - sy);
        }
      })();
      {
        const dist = (() => {
          {
            const $t27927 = (() => {
              {
                const $t27925 = (dx * dx);
                {
                  const $t27926 = (dy * dy);
                  return ($t27925 + $t27926);
                }
              }
            })();
            return Math.sqrt($t27927);
          }
        })();
        {
          const $t27928 = (dist > 0.);
          if ($t27928 === true) {
            return (() => {
              {
                const $t27931 = (() => {
                  {
                    const $t27929 = (dx / dist);
                    return ($t27929 * 150.);
                  }
                })();
                {
                  const $t27934 = (() => {
                    {
                      const $t27932 = (dy / dist);
                      return ($t27932 * 150.);
                    }
                  })();
                  return ({ x: sx, y: sy, vx: $t27931, vy: $t27934, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
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
        const $t27938 = (() => {
          {
            const go_i4615 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t274_i4616 = { $: "Nil" };
              return go$apply$4761(go_i4615, acc, $t274_i4616);
            }
          }
        })();
        {
          const $t27939 = game.enemy_shots;
          {
            const $t27940 = (() => {
              {
                const go_i4612 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                {
                  const $t282_i4613 = (() => {
                    {
                      const go_i11951 = { $: "$Clo_go$5256", _0: go$apply$5256 };
                      {
                        const $t274_i11952 = { $: "Nil" };
                        return go$apply$5256(go_i11951, new_shots, $t274_i11952);
                      }
                    }
                  })();
                  return go$apply$4759(go_i4612, $t282_i4613, $t27939);
                }
              }
            })();
            return ({ ...game, ships: $t27938, enemy_shots: $t27940 });
          }
        }
      }
      break;
    }
    case "Cons": {
      const $f28051 = ships._0;
      const $f28052 = ships._1;
      {
        const rest = $f28052;
        {
          const sh = $f28051;
          {
            const $t27941 = sh.mode;
            switch ($t27941.$) {
              case "ShipOrbiting": {
                const $f28044 = $t27941._0;
                {
                  const angle = (() => {
                    return $f28044;
                  })();
                  {
                    const $t27943 = (() => {
                      {
                        const $t27942 = sh.star_idx;
                        return Perihelion$Core$star_at(game, $t27942);
                      }
                    })();
                    switch ($t27943.$) {
                      case "None": {
                        return Perihelion$Combat$step_ships_go(game, rest, acc, new_shots, dt_s);
                        break;
                      }
                      case "Some": {
                        const $f28009 = $t27943._0;
                        {
                          const s = $f28009;
                          {
                            const idle2 = (() => {
                              {
                                const $t27944 = sh.idle_timer;
                                return ($t27944 - dt_s);
                              }
                            })();
                            {
                              const $t27945 = (idle2 <= 0.);
                              if ($t27945 === true) {
                                return (() => {
                                  {
                                    const $p27980 = (() => {
                                      {
                                        const $t27946 = sh.hunter;
                                        if ($t27946 === true) {
                                          return (() => {
                                            {
                                              const $t27947 = game.ball_x;
                                              {
                                                const $t27948 = game.ball_y;
                                                return { _0: $t27947, _1: $t27948 };
                                              }
                                            }
                                          })();
                                        } else {
                                          return (() => {
                                            {
                                              const $t27949 = sh.x;
                                              {
                                                const $t27950 = sh.y;
                                                return { _0: $t27949, _1: $t27950 };
                                              }
                                            }
                                          })();
                                        }
                                      }
                                    })();
                                    {
                                      const tx = $p27980._0;
                                      {
                                        const ty = $p27980._1;
                                        {
                                          const $t27954 = (() => {
                                            {
                                              const $t27951 = sh.star_idx;
                                              {
                                                const $t27952 = game.stars;
                                                {
                                                  const $t27953 = { $: "None" };
                                                  return Perihelion$Combat$nearest_other_star(tx, ty, $t27951, $t27952, 0, $t27953, 999999999.);
                                                }
                                              }
                                            }
                                          })();
                                          switch ($t27954.$) {
                                            case "None": {
                                              {
                                                const sh2 = ({ ...sh, idle_timer: 6. });
                                                {
                                                  const $t27956 = { $: "Cons", _0: sh2, _1: acc };
                                                  return Perihelion$Combat$step_ships_go(game, rest, $t27956, new_shots, dt_s);
                                                }
                                              }
                                              break;
                                            }
                                            case "Some": {
                                              const $f27979 = $t27954._0;
                                              {
                                                const target_idx = $f27979;
                                                {
                                                  const $t27957 = Perihelion$Core$star_at(game, target_idx);
                                                  switch ($t27957.$) {
                                                    case "None": {
                                                      {
                                                        const sh2 = ({ ...sh, idle_timer: 6. });
                                                        {
                                                          const $t27959 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t27959, new_shots, dt_s);
                                                        }
                                                      }
                                                      break;
                                                    }
                                                    case "Some": {
                                                      const $f27978 = $t27957._0;
                                                      {
                                                        const t = $f27978;
                                                        {
                                                          const dx = (() => {
                                                            {
                                                              const $t27960 = t.x;
                                                              {
                                                                const $t27961 = sh.x;
                                                                return ($t27960 - $t27961);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const dy = (() => {
                                                              {
                                                                const $t27962 = t.y;
                                                                {
                                                                  const $t27963 = sh.y;
                                                                  return ($t27962 - $t27963);
                                                                }
                                                              }
                                                            })();
                                                            {
                                                              const dist = (() => {
                                                                {
                                                                  const $t27966 = (() => {
                                                                    {
                                                                      const $t27964 = (dx * dx);
                                                                      {
                                                                        const $t27965 = (dy * dy);
                                                                        return ($t27964 + $t27965);
                                                                      }
                                                                    }
                                                                  })();
                                                                  return Math.sqrt($t27966);
                                                                }
                                                              })();
                                                              {
                                                                const vel = (() => {
                                                                  {
                                                                    const $t27967 = (dist > 0.);
                                                                    if ($t27967 === true) {
                                                                      return (() => {
                                                                        {
                                                                          const $t27970 = (() => {
                                                                            {
                                                                              const $t27968 = (dx / dist);
                                                                              return ($t27968 * 180.);
                                                                            }
                                                                          })();
                                                                          {
                                                                            const $t27973 = (() => {
                                                                              {
                                                                                const $t27971 = (dy / dist);
                                                                                return ($t27971 * 180.);
                                                                              }
                                                                            })();
                                                                            return { _0: $t27970, _1: $t27973 };
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
                                                                          const $t27975 = { $: "ShipFlying", _0: vx, _1: vy };
                                                                          return ({ ...sh, mode: $t27975 });
                                                                        }
                                                                      })();
                                                                      {
                                                                        const $t27976 = { $: "Cons", _0: sh2, _1: acc };
                                                                        return Perihelion$Combat$step_ships_go(game, rest, $t27976, new_shots, dt_s);
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
                                          const $t27985 = (() => {
                                            {
                                              const $t27984 = (d * 1.4);
                                              return ($t27984 * dt_s);
                                            }
                                          })();
                                          return (angle + $t27985);
                                        }
                                      })();
                                      {
                                        const r = (() => {
                                          {
                                            const $t27986 = s.capture_radius;
                                            return ($t27986 * 1.6);
                                          }
                                        })();
                                        {
                                          const sx = (() => {
                                            {
                                              const $t27988 = s.x;
                                              {
                                                const $t27990 = (() => {
                                                  {
                                                    const $t27989 = Math.cos(angle2);
                                                    return ($t27989 * r);
                                                  }
                                                })();
                                                return ($t27988 + $t27990);
                                              }
                                            }
                                          })();
                                          {
                                            const sy = (() => {
                                              {
                                                const $t27991 = s.y;
                                                {
                                                  const $t27993 = (() => {
                                                    {
                                                      const $t27992 = Math.sin(angle2);
                                                      return ($t27992 * r);
                                                    }
                                                  })();
                                                  return ($t27991 + $t27993);
                                                }
                                              }
                                            })();
                                            {
                                              const cd2 = (() => {
                                                {
                                                  const $t27994 = sh.fire_cooldown;
                                                  return ($t27994 - dt_s);
                                                }
                                              })();
                                              {
                                                const in_range = (() => {
                                                  {
                                                    const $t27997 = (() => {
                                                      {
                                                        const $t27995 = game.ball_x;
                                                        {
                                                          const $t27996 = game.ball_y;
                                                          {
                                                            const dx_i4623 = ($t27995 - sx);
                                                            {
                                                              const dy_i4624 = ($t27996 - sy);
                                                              {
                                                                const $t27600_i4625 = (dx_i4623 * dx_i4623);
                                                                {
                                                                  const $t27601_i4626 = (dy_i4624 * dy_i4624);
                                                                  return ($t27600_i4625 + $t27601_i4626);
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    })();
                                                    {
                                                      const $t28000 = (380. * 380.);
                                                      return ($t27997 <= $t28000);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28002 = (() => {
                                                    {
                                                      const $t28001 = (cd2 <= 0.);
                                                      return ($t28001 && in_range);
                                                    }
                                                  })();
                                                  if ($t28002 === true) {
                                                    return (() => {
                                                      {
                                                        const shot = Perihelion$Combat$ship_fire_shot(sx, sy, game);
                                                        {
                                                          const sh2 = (() => {
                                                            {
                                                              const $t28003 = { $: "ShipOrbiting", _0: angle2 };
                                                              return ({ ...sh, x: sx, y: sy, mode: $t28003, idle_timer: idle2, fire_cooldown: 2.5 });
                                                            }
                                                          })();
                                                          {
                                                            const $t28005 = { $: "Cons", _0: sh2, _1: acc };
                                                            {
                                                              const $t28006 = { $: "Cons", _0: shot, _1: new_shots };
                                                              return Perihelion$Combat$step_ships_go(game, rest, $t28005, $t28006, dt_s);
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
                                                            const $t28007 = { $: "ShipOrbiting", _0: angle2 };
                                                            return ({ ...sh, x: sx, y: sy, mode: $t28007, idle_timer: idle2, fire_cooldown: cd2 });
                                                          }
                                                        })();
                                                        {
                                                          const $t28008 = { $: "Cons", _0: sh2, _1: acc };
                                                          return Perihelion$Combat$step_ships_go(game, rest, $t28008, new_shots, dt_s);
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
                const $f28045 = $t27941._0;
                const $f28046 = $t27941._1;
                {
                  const vy = (() => {
                    return $f28046;
                  })();
                  {
                    const vx = (() => {
                      return $f28045;
                    })();
                    {
                      const x2 = (() => {
                        {
                          const $t28010 = sh.x;
                          {
                            const $t28011 = (vx * dt_s);
                            return ($t28010 + $t28011);
                          }
                        }
                      })();
                      {
                        const y2 = (() => {
                          {
                            const $t28012 = sh.y;
                            {
                              const $t28013 = (vy * dt_s);
                              return ($t28012 + $t28013);
                            }
                          }
                        })();
                        {
                          const $t28015 = (() => {
                            {
                              const $t28014 = game.stars;
                              return Perihelion$Combat$arrived_star($t28014, x2, y2, 0);
                            }
                          })();
                          switch ($t28015.$) {
                            case "Some": {
                              const $f28043 = $t28015._0;
                              {
                                const pair = $f28043;
                                {
                                  const idx = pair._0;
                                  {
                                    const t = pair._1;
                                    {
                                      const angle = (() => {
                                        {
                                          const $t28017 = (() => {
                                            {
                                              const $t28016 = t.y;
                                              return (y2 - $t28016);
                                            }
                                          })();
                                          {
                                            const $t28019 = (() => {
                                              {
                                                const $t28018 = t.x;
                                                return (x2 - $t28018);
                                              }
                                            })();
                                            return Math.atan2($t28017, $t28019);
                                          }
                                        }
                                      })();
                                      {
                                        const $p28039 = (() => {
                                          {
                                            const $t28020 = game.rng;
                                            {
                                              const $p29256_i5182_i11954 = (() => {
                                                {
                                                  const $p15861_i12663 = (() => {
                                                    {
                                                      const $p15858_i1974_i12654 = Random$next_raw($t28020);
                                                      {
                                                        const hi_i1975_i12655 = $p15858_i1974_i12654._0;
                                                        {
                                                          const rng2_i1976_i12656 = $p15858_i1974_i12654._1;
                                                          {
                                                            const $p15857_i1977_i12657 = Random$next_raw(rng2_i1976_i12656);
                                                            {
                                                              const lo_i1978_i12658 = $p15857_i1977_i12657._0;
                                                              {
                                                                const rng3_i1979_i12659 = $p15857_i1977_i12657._1;
                                                                {
                                                                  const $t15856_i1983_i12662 = (() => {
                                                                    {
                                                                      const $t15855_i1982_i12661 = (() => {
                                                                        {
                                                                          const $t15853_i1980_i12660 = march_int_and(hi_i1975_i12655, 1048575);
                                                                          return ($t15853_i1980_i12660 * 4294967296);
                                                                        }
                                                                      })();
                                                                      return ($t15855_i1982_i12661 + lo_i1978_i12658);
                                                                    }
                                                                  })();
                                                                  return { _0: $t15856_i1983_i12662, _1: rng3_i1979_i12659 };
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const bits_i12664 = $p15861_i12663._0;
                                                    {
                                                      const rng2_i12665 = $p15861_i12663._1;
                                                      {
                                                        const $t15860_i12667 = (() => {
                                                          {
                                                            const $t15859_i12666 = bits_i12664;
                                                            return ($t15859_i12666 / 4.50359962737e+15);
                                                          }
                                                        })();
                                                        return { _0: $t15860_i12667, _1: rng2_i12665 };
                                                      }
                                                    }
                                                  }
                                                }
                                              })();
                                              {
                                                const t_i5183_i11955 = $p29256_i5182_i11954._0;
                                                {
                                                  const rng2_i5184_i11956 = $p29256_i5182_i11954._1;
                                                  {
                                                    const out_i5185_i11957 = { _0: rng2_i5184_i11956, _1: t_i5183_i11955 };
                                                    return out_i5185_i11957;
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const rng2 = $p28039._0;
                                          {
                                            const idle_f = $p28039._1;
                                            {
                                              const idle = (() => {
                                                {
                                                  const $t28025 = (() => {
                                                    {
                                                      const $t28024 = (6. - 3.);
                                                      return (idle_f * $t28024);
                                                    }
                                                  })();
                                                  return (3. + $t28025);
                                                }
                                              })();
                                              {
                                                const r = (() => {
                                                  {
                                                    const $t28026 = t.capture_radius;
                                                    return ($t28026 * 1.6);
                                                  }
                                                })();
                                                {
                                                  const sh2 = (() => {
                                                    {
                                                      const $t28031 = (() => {
                                                        {
                                                          const $t28028 = t.x;
                                                          {
                                                            const $t28030 = (() => {
                                                              {
                                                                const $t28029 = Math.cos(angle);
                                                                return ($t28029 * r);
                                                              }
                                                            })();
                                                            return ($t28028 + $t28030);
                                                          }
                                                        }
                                                      })();
                                                      {
                                                        const $t28035 = (() => {
                                                          {
                                                            const $t28032 = t.y;
                                                            {
                                                              const $t28034 = (() => {
                                                                {
                                                                  const $t28033 = Math.sin(angle);
                                                                  return ($t28033 * r);
                                                                }
                                                              })();
                                                              return ($t28032 + $t28034);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const $t28036 = { $: "ShipOrbiting", _0: angle };
                                                          return ({ ...sh, x: $t28031, y: $t28035, star_idx: idx, mode: $t28036, idle_timer: idle });
                                                        }
                                                      }
                                                    }
                                                  })();
                                                  {
                                                    const $t28037 = ({ ...game, rng: rng2 });
                                                    {
                                                      const $t28038 = { $: "Cons", _0: sh2, _1: acc };
                                                      return Perihelion$Combat$step_ships_go($t28037, rest, $t28038, new_shots, dt_s);
                                                    }
                                                  }
                                                }
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
                                const $t28041 = Perihelion$Combat$in_band(game, x2, y2);
                                if ($t28041 === true) {
                                  return (() => {
                                    {
                                      const sh2 = ({ ...sh, x: x2, y: y2 });
                                      {
                                        const $t28042 = { $: "Cons", _0: sh2, _1: acc };
                                        return Perihelion$Combat$step_ships_go(game, rest, $t28042, new_shots, dt_s);
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
    const $t28057 = game.mode;
    switch ($t28057.$) {
      case "Orbiting": {
        const $f28078 = $t28057._0;
        const $f28079 = $t28057._1;
        const $f28080 = $t28057._2;
        {
          const idx = (() => {
            return $f28078;
          })();
          {
            const $t28058 = Perihelion$Core$star_at(game, idx);
            switch ($t28058.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f28070 = $t28058._0;
                {
                  const s = $f28070;
                  {
                    const rdx = (() => {
                      {
                        const $t28059 = game.ball_x;
                        {
                          const $t28060 = s.x;
                          return ($t28059 - $t28060);
                        }
                      }
                    })();
                    {
                      const rdy = (() => {
                        {
                          const $t28061 = game.ball_y;
                          {
                            const $t28062 = s.y;
                            return ($t28061 - $t28062);
                          }
                        }
                      })();
                      {
                        const rdist = (() => {
                          {
                            const $t28065 = (() => {
                              {
                                const $t28063 = (rdx * rdx);
                                {
                                  const $t28064 = (rdy * rdy);
                                  return ($t28063 + $t28064);
                                }
                              }
                            })();
                            return Math.sqrt($t28065);
                          }
                        })();
                        {
                          const $t28066 = (rdist > 0.);
                          if ($t28066 === true) {
                            return (() => {
                              {
                                const $t28067 = (rdx / rdist);
                                {
                                  const $t28068 = (rdy / rdist);
                                  {
                                    const $t28069 = { _0: $t28067, _1: $t28068 };
                                    return { $: "Some", _0: $t28069 };
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
        const $f28089 = $t28057._0;
        const $f28090 = $t28057._1;
        {
          const vy = (() => {
            return $f28090;
          })();
          {
            const vx = (() => {
              return $f28089;
            })();
            {
              const speed = (() => {
                {
                  const $t28073 = (() => {
                    {
                      const $t28071 = (vx * vx);
                      {
                        const $t28072 = (vy * vy);
                        return ($t28071 + $t28072);
                      }
                    }
                  })();
                  return Math.sqrt($t28073);
                }
              })();
              {
                const $t28074 = (speed > 0.);
                if ($t28074 === true) {
                  return (() => {
                    {
                      const $t28075 = (vx / speed);
                      {
                        const $t28076 = (vy / speed);
                        {
                          const $t28077 = { _0: $t28075, _1: $t28076 };
                          return { $: "Some", _0: $t28077 };
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
    const $t28095 = game.mode;
    switch ($t28095.$) {
      case "Orbiting": {
        const $f28103 = $t28095._0;
        const $f28104 = $t28095._1;
        const $f28105 = $t28095._2;
        return game;
        break;
      }
      case "Flying": {
        const $f28114 = $t28095._0;
        const $f28115 = $t28095._1;
        {
          const vy = (() => {
            return $f28115;
          })();
          {
            const vx = (() => {
              return $f28114;
            })();
            {
              const $t28102 = (() => {
                {
                  const $t28098 = (() => {
                    {
                      const $t28097 = (ax * 14.);
                      return (vx - $t28097);
                    }
                  })();
                  {
                    const $t28101 = (() => {
                      {
                        const $t28100 = (ay * 14.);
                        return (vy - $t28100);
                      }
                    })();
                    return { $: "Flying", _0: $t28098, _1: $t28101 };
                  }
                }
              })();
              return ({ ...game, mode: $t28102 });
            }
          }
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
    const $p28161 = (() => {
      {
        const $t28141 = (0. - 0.5236);
        {
          const $t28134_i4739 = (() => {
            {
              const $t28131_i4736 = (() => {
                {
                  const $t28130_i4735 = Math.cos($t28141);
                  return (ax * $t28130_i4735);
                }
              })();
              {
                const $t28133_i4738 = (() => {
                  {
                    const $t28132_i4737 = Math.sin($t28141);
                    return (ay * $t28132_i4737);
                  }
                })();
                return ($t28131_i4736 - $t28133_i4738);
              }
            }
          })();
          {
            const $t28139_i4744 = (() => {
              {
                const $t28136_i4741 = (() => {
                  {
                    const $t28135_i4740 = Math.sin($t28141);
                    return (ax * $t28135_i4740);
                  }
                })();
                {
                  const $t28138_i4743 = (() => {
                    {
                      const $t28137_i4742 = Math.cos($t28141);
                      return (ay * $t28137_i4742);
                    }
                  })();
                  return ($t28136_i4741 + $t28138_i4743);
                }
              }
            })();
            return { _0: $t28134_i4739, _1: $t28139_i4744 };
          }
        }
      }
    })();
    {
      const a1x = $p28161._0;
      {
        const a1y = $p28161._1;
        {
          const $p28160 = (() => {
            {
              const $t28144 = (() => {
                {
                  const $t28143 = (0.5236 / 2.);
                  return (0. - $t28143);
                }
              })();
              {
                const $t28134_i4726 = (() => {
                  {
                    const $t28131_i4723 = (() => {
                      {
                        const $t28130_i4722 = Math.cos($t28144);
                        return (ax * $t28130_i4722);
                      }
                    })();
                    {
                      const $t28133_i4725 = (() => {
                        {
                          const $t28132_i4724 = Math.sin($t28144);
                          return (ay * $t28132_i4724);
                        }
                      })();
                      return ($t28131_i4723 - $t28133_i4725);
                    }
                  }
                })();
                {
                  const $t28139_i4731 = (() => {
                    {
                      const $t28136_i4728 = (() => {
                        {
                          const $t28135_i4727 = Math.sin($t28144);
                          return (ax * $t28135_i4727);
                        }
                      })();
                      {
                        const $t28138_i4730 = (() => {
                          {
                            const $t28137_i4729 = Math.cos($t28144);
                            return (ay * $t28137_i4729);
                          }
                        })();
                        return ($t28136_i4728 + $t28138_i4730);
                      }
                    }
                  })();
                  return { _0: $t28134_i4726, _1: $t28139_i4731 };
                }
              }
            }
          })();
          {
            const a2x = $p28160._0;
            {
              const a2y = $p28160._1;
              {
                const $p28159 = (() => {
                  {
                    const $t28146 = (0.5236 / 2.);
                    {
                      const $t28134_i4713 = (() => {
                        {
                          const $t28131_i4710 = (() => {
                            {
                              const $t28130_i4709 = Math.cos($t28146);
                              return (ax * $t28130_i4709);
                            }
                          })();
                          {
                            const $t28133_i4712 = (() => {
                              {
                                const $t28132_i4711 = Math.sin($t28146);
                                return (ay * $t28132_i4711);
                              }
                            })();
                            return ($t28131_i4710 - $t28133_i4712);
                          }
                        }
                      })();
                      {
                        const $t28139_i4718 = (() => {
                          {
                            const $t28136_i4715 = (() => {
                              {
                                const $t28135_i4714 = Math.sin($t28146);
                                return (ax * $t28135_i4714);
                              }
                            })();
                            {
                              const $t28138_i4717 = (() => {
                                {
                                  const $t28137_i4716 = Math.cos($t28146);
                                  return (ay * $t28137_i4716);
                                }
                              })();
                              return ($t28136_i4715 + $t28138_i4717);
                            }
                          }
                        })();
                        return { _0: $t28134_i4713, _1: $t28139_i4718 };
                      }
                    }
                  }
                })();
                {
                  const a3x = $p28159._0;
                  {
                    const a3y = $p28159._1;
                    {
                      const $p28158 = (() => {
                        {
                          const $t28134_i4700 = (() => {
                            {
                              const $t28131_i4697 = (() => {
                                {
                                  const $t28130_i4696 = Math.cos(0.5236);
                                  return (ax * $t28130_i4696);
                                }
                              })();
                              {
                                const $t28133_i4699 = (() => {
                                  {
                                    const $t28132_i4698 = Math.sin(0.5236);
                                    return (ay * $t28132_i4698);
                                  }
                                })();
                                return ($t28131_i4697 - $t28133_i4699);
                              }
                            }
                          })();
                          {
                            const $t28139_i4705 = (() => {
                              {
                                const $t28136_i4702 = (() => {
                                  {
                                    const $t28135_i4701 = Math.sin(0.5236);
                                    return (ax * $t28135_i4701);
                                  }
                                })();
                                {
                                  const $t28138_i4704 = (() => {
                                    {
                                      const $t28137_i4703 = Math.cos(0.5236);
                                      return (ay * $t28137_i4703);
                                    }
                                  })();
                                  return ($t28136_i4702 + $t28138_i4704);
                                }
                              }
                            })();
                            return { _0: $t28134_i4700, _1: $t28139_i4705 };
                          }
                        }
                      })();
                      {
                        const a4x = $p28158._0;
                        {
                          const a4y = $p28158._1;
                          {
                            const $t28148 = (() => {
                              {
                                const $t28121_i4689 = (ax * 420.);
                                {
                                  const $t28123_i4691 = (ay * 420.);
                                  return ({ x: x, y: y, vx: $t28121_i4689, vy: $t28123_i4691, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                }
                              }
                            })();
                            {
                              const $t28149 = (() => {
                                {
                                  const $t28121_i4680 = (a1x * 420.);
                                  {
                                    const $t28123_i4682 = (a1y * 420.);
                                    return ({ x: x, y: y, vx: $t28121_i4680, vy: $t28123_i4682, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                  }
                                }
                              })();
                              {
                                const $t28150 = (() => {
                                  {
                                    const $t28121_i4671 = (a2x * 420.);
                                    {
                                      const $t28123_i4673 = (a2y * 420.);
                                      return ({ x: x, y: y, vx: $t28121_i4671, vy: $t28123_i4673, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                    }
                                  }
                                })();
                                {
                                  const $t28151 = (() => {
                                    {
                                      const $t28121_i4662 = (a3x * 420.);
                                      {
                                        const $t28123_i4664 = (a3y * 420.);
                                        return ({ x: x, y: y, vx: $t28121_i4662, vy: $t28123_i4664, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                      }
                                    }
                                  })();
                                  {
                                    const $t28152 = (() => {
                                      {
                                        const $t28121_i4653 = (a4x * 420.);
                                        {
                                          const $t28123_i4655 = (a4y * 420.);
                                          return ({ x: x, y: y, vx: $t28121_i4653, vy: $t28123_i4655, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                        }
                                      }
                                    })();
                                    {
                                      const $t28153 = { $: "Nil" };
                                      {
                                        const $t28154 = { $: "Cons", _0: $t28152, _1: $t28153 };
                                        {
                                          const $t28155 = { $: "Cons", _0: $t28151, _1: $t28154 };
                                          {
                                            const $t28156 = { $: "Cons", _0: $t28150, _1: $t28155 };
                                            {
                                              const $t28157 = { $: "Cons", _0: $t28149, _1: $t28156 };
                                              return { $: "Cons", _0: $t28148, _1: $t28157 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t28162 = Perihelion$Core$active_weapon(game);
    switch ($t28162.$) {
      case "StarKiller": {
        {
          const $t28163 = game.starkiller_cooldown;
          return ($t28163 > 0.);
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
        const $t28165 = { $: "$Clo_$lam28164$3716", _0: $lam28164$apply$3716 };
        return List$any$List_String$Fn_String_Bool(keys, $t28165);
      }
    })();
    {
      const $t28171 = (() => {
        {
          const $t28169 = (() => {
            {
              const $t28166 = (!pressed);
              {
                const $t28168 = (() => {
                  {
                    const $t28167 = game.fire_cooldown;
                    return ($t28167 > 0.);
                  }
                })();
                return ($t28166 || $t28168);
              }
            }
          })();
          {
            const $t28170 = Perihelion$Combat$starkiller_on_cooldown(game);
            return ($t28169 || $t28170);
          }
        }
      })();
      if ($t28171 === true) {
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
                    const $t28172 = cy;
                    {
                      const $t28173 = game.camera_y;
                      return ($t28172 + $t28173);
                    }
                  }
                })();
                {
                  const dx = (() => {
                    {
                      const $t28174 = cx;
                      {
                        const $t28175 = game.ball_x;
                        return ($t28174 - $t28175);
                      }
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t28176 = game.ball_y;
                        return (cursor_world_y - $t28176);
                      }
                    })();
                    {
                      const dist = (() => {
                        {
                          const $t28179 = (() => {
                            {
                              const $t28177 = (dx * dx);
                              {
                                const $t28178 = (dy * dy);
                                return ($t28177 + $t28178);
                              }
                            }
                          })();
                          return Math.sqrt($t28179);
                        }
                      })();
                      {
                        const aim = (() => {
                          {
                            const $t28180 = (dist > 0.);
                            if ($t28180 === true) {
                              return (() => {
                                {
                                  const $t28181 = (dx / dist);
                                  {
                                    const $t28182 = (dy / dist);
                                    {
                                      const $t28183 = { _0: $t28181, _1: $t28182 };
                                      return { $: "Some", _0: $t28183 };
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
                            const $f28230 = aim._0;
                            {
                              const pair = $f28230;
                              {
                                const ax = pair._0;
                                {
                                  const ay = pair._1;
                                  {
                                    const g2 = Perihelion$Combat$apply_recoil(game, ax, ay);
                                    {
                                      const $t28184 = Perihelion$Core$active_weapon(game);
                                      {
                                        let new_shots;
                                        switch ($t28184.$) {
                                          case "Base": {
                                            new_shots = (() => {
                                              {
                                                const $t28187 = (() => {
                                                  {
                                                    const $t28185 = game.ball_x;
                                                    {
                                                      const $t28186 = game.ball_y;
                                                      {
                                                        const $t28121_i4766 = (ax * 420.);
                                                        {
                                                          const $t28123_i4768 = (ay * 420.);
                                                          return ({ x: $t28185, y: $t28186, vx: $t28121_i4766, vy: $t28123_i4768, ttl: 3., homing: false, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28188 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t28187, _1: $t28188 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Homing": {
                                            new_shots = (() => {
                                              {
                                                const $t28191 = (() => {
                                                  {
                                                    const $t28189 = game.ball_x;
                                                    {
                                                      const $t28190 = game.ball_y;
                                                      {
                                                        const $t28126_i4775 = (ax * 420.);
                                                        {
                                                          const $t28128_i4777 = (ay * 420.);
                                                          return ({ x: $t28189, y: $t28190, vx: $t28126_i4775, vy: $t28128_i4777, ttl: 3., homing: true, star_killer: false, target_x: 0., target_y: 0. });
                                                        }
                                                      }
                                                    }
                                                  }
                                                })();
                                                {
                                                  const $t28192 = { $: "Nil" };
                                                  return { $: "Cons", _0: $t28191, _1: $t28192 };
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "Spread": {
                                            new_shots = (() => {
                                              {
                                                const $t28193 = game.ball_x;
                                                {
                                                  const $t28194 = game.ball_y;
                                                  return Perihelion$Combat$spread_shots($t28193, $t28194, ax, ay);
                                                }
                                              }
                                            })();
                                            break;
                                          }
                                          case "StarKiller": {
                                            new_shots = (() => {
                                              {
                                                const $t28196 = (() => {
                                                  {
                                                    const $t28195 = Perihelion$Combat$starkiller_target_idx(game);
                                                    return Perihelion$Core$star_at(game, $t28195);
                                                  }
                                                })();
                                                switch ($t28196.$) {
                                                  case "None": {
                                                    return { $: "Nil" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f28219 = $t28196._0;
                                                    {
                                                      const target = $f28219;
                                                      {
                                                        const tdx = (() => {
                                                          {
                                                            const $t28197 = target.x;
                                                            {
                                                              const $t28198 = game.ball_x;
                                                              return ($t28197 - $t28198);
                                                            }
                                                          }
                                                        })();
                                                        {
                                                          const tdy = (() => {
                                                            {
                                                              const $t28199 = target.y;
                                                              {
                                                                const $t28200 = game.ball_y;
                                                                return ($t28199 - $t28200);
                                                              }
                                                            }
                                                          })();
                                                          {
                                                            const tdist = (() => {
                                                              {
                                                                const $t28203 = (() => {
                                                                  {
                                                                    const $t28201 = (tdx * tdx);
                                                                    {
                                                                      const $t28202 = (tdy * tdy);
                                                                      return ($t28201 + $t28202);
                                                                    }
                                                                  }
                                                                })();
                                                                return Math.sqrt($t28203);
                                                              }
                                                            })();
                                                            {
                                                              const $t28204 = (tdist <= 0.);
                                                              if ($t28204 === true) {
                                                                return { $: "Nil" };
                                                              } else {
                                                                return (() => {
                                                                  {
                                                                    const $t28217 = (() => {
                                                                      {
                                                                        const $t28205 = game.ball_x;
                                                                        {
                                                                          const $t28206 = game.ball_y;
                                                                          {
                                                                            const $t28209 = (() => {
                                                                              {
                                                                                const $t28207 = (tdx / tdist);
                                                                                return ($t28207 * 420.);
                                                                              }
                                                                            })();
                                                                            {
                                                                              const $t28212 = (() => {
                                                                                {
                                                                                  const $t28210 = (tdy / tdist);
                                                                                  return ($t28210 * 420.);
                                                                                }
                                                                              })();
                                                                              {
                                                                                const $t28214 = (3. * 3.);
                                                                                {
                                                                                  const $t28215 = target.x;
                                                                                  {
                                                                                    const $t28216 = target.y;
                                                                                    return ({ x: $t28205, y: $t28206, vx: $t28209, vy: $t28212, ttl: $t28214, homing: false, star_killer: true, target_x: $t28215, target_y: $t28216 });
                                                                                  }
                                                                                }
                                                                              }
                                                                            }
                                                                          }
                                                                        }
                                                                      }
                                                                    })();
                                                                    {
                                                                      const $t28218 = { $: "Nil" };
                                                                      return { $: "Cons", _0: $t28217, _1: $t28218 };
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
                                              const $t28220 = Perihelion$Core$active_weapon(game);
                                              switch ($t28220.$) {
                                                case "StarKiller": {
                                                  return game.fire_cooldown;
                                                  break;
                                                }
                                                default: {
                                                  {
                                                    const reduced_i4757 = (() => {
                                                      {
                                                        const $t27589_i4756 = (() => {
                                                          {
                                                            const $t27587_i4754 = (() => {
                                                              {
                                                                const $t27586_i4753 = game.fire_rate_stacks;
                                                                return $t27586_i4753;
                                                              }
                                                            })();
                                                            return ($t27587_i4754 * 0.05);
                                                          }
                                                        })();
                                                        return (0.4 - $t27589_i4756);
                                                      }
                                                    })();
                                                    {
                                                      const $t27591_i4759 = (reduced_i4757 < 0.15);
                                                      if ($t27591_i4759 === true) {
                                                        return 0.15;
                                                      } else {
                                                        return reduced_i4757;
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
                                                const $t28223 = Perihelion$Core$active_weapon(game);
                                                switch ($t28223.$) {
                                                  case "StarKiller": {
                                                    {
                                                      let $t28224;
                                                      switch (new_shots.$) {
                                                        case "Nil": {
                                                          $t28224 = true;
                                                          break;
                                                        }
                                                        default: {
                                                          $t28224 = false;
                                                          break;
                                                        }
                                                      }
                                                      if ($t28224 === true) {
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
                                              const $t28227 = g2.player_shots;
                                              {
                                                const $t28228 = (() => {
                                                  {
                                                    const go_i4748 = { $: "$Clo_go$4759", _0: go$apply$4759 };
                                                    {
                                                      const $t282_i4749 = (() => {
                                                        {
                                                          const go_i11975 = { $: "$Clo_go$5256", _0: go$apply$5256 };
                                                          {
                                                            const $t274_i11976 = { $: "Nil" };
                                                            return go$apply$5256(go_i11975, $t28227, $t274_i11976);
                                                          }
                                                        }
                                                      })();
                                                      return go$apply$4759(go_i4748, $t282_i4749, new_shots);
                                                    }
                                                  }
                                                })();
                                                return ({ ...g2, player_shots: $t28228, fire_cooldown: cooldown2, starkiller_cooldown: starkiller_cd2 });
                                              }
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
      const $f28246 = stars._0;
      const $f28247 = stars._1;
      {
        const rest = (() => {
          return $f28247;
        })();
        {
          const s = (() => {
            return $f28246;
          })();
          {
            const $t28244 = (() => {
              {
                const $t28242 = s.x;
                {
                  const $t28243 = s.y;
                  {
                    const $t27602_i4797 = (() => {
                      {
                        const dx_i11981 = (tx - $t28242);
                        {
                          const dy_i11982 = (ty - $t28243);
                          {
                            const $t27600_i11983 = (dx_i11981 * dx_i11981);
                            {
                              const $t27601_i11984 = (dy_i11982 * dy_i11982);
                              return ($t27600_i11983 + $t27601_i11984);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27605_i4800 = (() => {
                        {
                          const $t27603_i4798 = (0.001 + 0.);
                          {
                            const $t27604_i4799 = (0.001 + 0.);
                            return ($t27603_i4798 * $t27604_i4799);
                          }
                        }
                      })();
                      return ($t27602_i4797 <= $t27605_i4800);
                    }
                  }
                }
              }
            })();
            if ($t28244 === true) {
              return { $: "Some", _0: i };
            } else {
              return (() => {
                {
                  const $t28245 = (i + 1);
                  return Perihelion$Combat$find_star_by_pos(rest, tx, ty, $t28245);
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
    const $t28252 = game.player_shots;
    {
      const $t28254 = { $: "$Clo_$lam28253$3722", _0: $lam28253$apply$3722 };
      {
        const sk_shots = (() => {
          {
            const pred_i4827 = $t28254;
            {
              const go_i4828 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4827 };
              {
                const $t323_i4829 = { $: "Nil" };
                return go$apply$4753(go_i4828, $t28252, $t323_i4829);
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
            const $f28278 = sk_shots._0;
            const $f28279 = sk_shots._1;
            {
              const s = $f28278;
              {
                const $t28260 = (() => {
                  {
                    const $t28255 = s.x;
                    {
                      const $t28256 = s.y;
                      {
                        const $t28258 = s.target_x;
                        {
                          const $t28259 = s.target_y;
                          {
                            const $t27602_i4822 = (() => {
                              {
                                const dx_i11997 = ($t28258 - $t28255);
                                {
                                  const dy_i11998 = ($t28259 - $t28256);
                                  {
                                    const $t27600_i11999 = (dx_i11997 * dx_i11997);
                                    {
                                      const $t27601_i12000 = (dy_i11998 * dy_i11998);
                                      return ($t27600_i11999 + $t27601_i12000);
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const $t27605_i4825 = (() => {
                                {
                                  const $t27603_i4823 = (20. + 0.);
                                  {
                                    const $t27604_i4824 = (20. + 0.);
                                    return ($t27603_i4823 * $t27604_i4824);
                                  }
                                }
                              })();
                              return ($t27602_i4822 <= $t27605_i4825);
                            }
                          }
                        }
                      }
                    }
                  }
                })();
                if ($t28260 === true) {
                  return (() => {
                    {
                      const $t28264 = (() => {
                        {
                          const $t28261 = game.stars;
                          {
                            const $t28262 = s.target_x;
                            {
                              const $t28263 = s.target_y;
                              return Perihelion$Combat$find_star_by_pos($t28261, $t28262, $t28263, 0);
                            }
                          }
                        }
                      })();
                      switch ($t28264.$) {
                        case "None": {
                          {
                            const $t28265 = game.player_shots;
                            {
                              const $t28268 = { $: "$Clo_$lam28266$3724", _0: $lam28266$apply$3724 };
                              {
                                const $t28269 = (() => {
                                  {
                                    const pred_i4804 = $t28268;
                                    {
                                      const go_i4805 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4804 };
                                      {
                                        const $t323_i4806 = { $: "Nil" };
                                        return go$apply$4753(go_i4805, $t28265, $t323_i4806);
                                      }
                                    }
                                  }
                                })();
                                return ({ ...game, player_shots: $t28269 });
                              }
                            }
                          }
                          break;
                        }
                        case "Some": {
                          const $f28277 = $t28264._0;
                          {
                            const tidx = $f28277;
                            {
                              const g2 = Perihelion$Core$remove_star(game, tidx);
                              {
                                const $t28270 = g2.ships;
                                {
                                  const $t28271 = (() => {
                                    {
                                      const $t28234_i4813 = { $: "$Clo_$lam28232$3719", _0: $lam28232$apply$3719, _1: tidx };
                                      {
                                        const $t28235_i4814 = (() => {
                                          {
                                            const pred_i11990 = $t28234_i4813;
                                            {
                                              const go_i11991 = { $: "$Clo_go$4765", _0: go$apply$4765, _1: pred_i11990 };
                                              {
                                                const $t323_i11992 = { $: "Nil" };
                                                return go$apply$4765(go_i11991, $t28270, $t323_i11992);
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const $t28241_i4815 = { $: "$Clo_$lam28236$3720", _0: $lam28236$apply$3720, _1: tidx };
                                          {
                                            const f_i11986 = $t28241_i4815;
                                            {
                                              const go_i11987 = { $: "$Clo_go$4763", _0: go$apply$4763, _1: f_i11986 };
                                              {
                                                const $t291_i11988 = { $: "Nil" };
                                                return go$apply$4763(go_i11987, $t28235_i4814, $t291_i11988);
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28272 = game.player_shots;
                                    {
                                      const $t28275 = { $: "$Clo_$lam28273$3725", _0: $lam28273$apply$3725 };
                                      {
                                        const $t28276 = (() => {
                                          {
                                            const pred_i4808 = $t28275;
                                            {
                                              const go_i4809 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4808 };
                                              {
                                                const $t323_i4810 = { $: "Nil" };
                                                return go$apply$4753(go_i4809, $t28272, $t323_i4810);
                                              }
                                            }
                                          }
                                        })();
                                        return ({ ...g2, ships: $t28271, player_shots: $t28276 });
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
    const $p28316 = (() => {
      {
        const $t28291 = game.asteroids;
        {
          const $t28299 = { $: "$Clo_$lam28292$3727", _0: $lam28292$apply$3727, _1: game };
          {
            const pred_i4853 = $t28299;
            {
              const go_i4854 = { $: "$Clo_go$4772", _0: go$apply$4772, _1: pred_i4853 };
              {
                const $t578_i4855 = { $: "Nil" };
                {
                  const $t579_i4856 = { $: "Nil" };
                  return go$apply$4772(go_i4854, $t28291, $t578_i4855, $t579_i4856);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28316._0;
      {
        const alive = $p28316._1;
        {
          const $t28300 = game.player_shots;
          {
            const $t28309 = { $: "$Clo_$lam28301$3729", _0: $lam28301$apply$3729, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i4849 = $t28309;
                  {
                    const go_i4850 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4849 };
                    {
                      const $t323_i4851 = { $: "Nil" };
                      return go$apply$4753(go_i4850, $t28300, $t323_i4851);
                    }
                  }
                }
              })();
              {
                const $t28314 = (() => {
                  {
                    const $t28310 = game.score;
                    {
                      const $t28313 = (() => {
                        {
                          const $t28311 = (() => {
                            {
                              const go_i4847 = { $: "$Clo_go$4769", _0: go$apply$4769 };
                              return go$apply$4769(go_i4847, dead, 0);
                            }
                          })();
                          {
                            const $t28312 = game.multiplier;
                            return ($t28311 * $t28312);
                          }
                        }
                      })();
                      return ($t28310 + $t28313);
                    }
                  }
                })();
                {
                  const $t28315 = (() => {
                    {
                      const $t28290_i4845 = { $: "$Clo_$lam28287$3726", _0: $lam28287$apply$3726 };
                      {
                        const f_i12010 = $t28290_i4845;
                        {
                          const go_i12011 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: f_i12010 };
                          {
                            const $t291_i12012 = { $: "Nil" };
                            return go$apply$4767(go_i12011, dead, $t291_i12012);
                          }
                        }
                      }
                    }
                  })();
                  return ({ ...game, asteroids: alive, player_shots: shots, score: $t28314, fx_bursts: $t28315 });
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
    const $p28338 = (() => {
      {
        const $t28319 = game.ships;
        {
          const $t28324 = { $: "$Clo_$lam28320$3731", _0: $lam28320$apply$3731, _1: game };
          {
            const pred_i4875 = $t28324;
            {
              const go_i4876 = { $: "$Clo_go$4778", _0: go$apply$4778, _1: pred_i4875 };
              {
                const $t578_i4877 = { $: "Nil" };
                {
                  const $t579_i4878 = { $: "Nil" };
                  return go$apply$4778(go_i4876, $t28319, $t578_i4877, $t579_i4878);
                }
              }
            }
          }
        }
      }
    })();
    {
      const dead = $p28338._0;
      {
        const alive = $p28338._1;
        {
          const $t28325 = game.player_shots;
          {
            const $t28331 = { $: "$Clo_$lam28326$3733", _0: $lam28326$apply$3733, _1: game };
            {
              const shots = (() => {
                {
                  const pred_i4871 = $t28331;
                  {
                    const go_i4872 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4871 };
                    {
                      const $t323_i4873 = { $: "Nil" };
                      return go$apply$4753(go_i4872, $t28325, $t323_i4873);
                    }
                  }
                }
              })();
              {
                const g2 = (() => {
                  {
                    const $t28337 = (() => {
                      {
                        const $t28332 = game.score;
                        {
                          const $t28336 = (() => {
                            {
                              const $t28334 = (() => {
                                {
                                  const $t28333 = (() => {
                                    {
                                      const go_i4869 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                                      return go$apply$4775(go_i4869, dead, 0);
                                    }
                                  })();
                                  {
                                    const sr_s1 = ($t28333 + $t28333);
                                    return sr_s1;
                                  }
                                }
                              })();
                              {
                                const $t28335 = game.multiplier;
                                return ($t28334 * $t28335);
                              }
                            }
                          })();
                          return ($t28332 + $t28336);
                        }
                      }
                    })();
                    return ({ ...game, ships: alive, player_shots: shots, score: $t28337 });
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
      const $f28364 = dead._0;
      const $f28365 = dead._1;
      {
        const rest = $f28365;
        {
          const sh = $f28364;
          {
            const pos = (() => {
              {
                const pos_i4888 = (() => {
                  {
                    const $t27598_i4886 = sh.x;
                    {
                      const $t27599_i4887 = sh.y;
                      return { _0: $t27598_i4886, _1: $t27599_i4887 };
                    }
                  }
                })();
                return pos_i4888;
              }
            })();
            {
              const sx = pos._0;
              {
                const sy = pos._1;
                {
                  const $p28362 = (() => {
                    {
                      const $t28339 = game.rng;
                      {
                        const $p29256_i5182_i12019 = (() => {
                          {
                            const $p15861_i12693 = (() => {
                              {
                                const $p15858_i1974_i12684 = Random$next_raw($t28339);
                                {
                                  const hi_i1975_i12685 = $p15858_i1974_i12684._0;
                                  {
                                    const rng2_i1976_i12686 = $p15858_i1974_i12684._1;
                                    {
                                      const $p15857_i1977_i12687 = Random$next_raw(rng2_i1976_i12686);
                                      {
                                        const lo_i1978_i12688 = $p15857_i1977_i12687._0;
                                        {
                                          const rng3_i1979_i12689 = $p15857_i1977_i12687._1;
                                          {
                                            const $t15856_i1983_i12692 = (() => {
                                              {
                                                const $t15855_i1982_i12691 = (() => {
                                                  {
                                                    const $t15853_i1980_i12690 = march_int_and(hi_i1975_i12685, 1048575);
                                                    return ($t15853_i1980_i12690 * 4294967296);
                                                  }
                                                })();
                                                return ($t15855_i1982_i12691 + lo_i1978_i12688);
                                              }
                                            })();
                                            return { _0: $t15856_i1983_i12692, _1: rng3_i1979_i12689 };
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const bits_i12694 = $p15861_i12693._0;
                              {
                                const rng2_i12695 = $p15861_i12693._1;
                                {
                                  const $t15860_i12697 = (() => {
                                    {
                                      const $t15859_i12696 = bits_i12694;
                                      return ($t15859_i12696 / 4.50359962737e+15);
                                    }
                                  })();
                                  return { _0: $t15860_i12697, _1: rng2_i12695 };
                                }
                              }
                            }
                          }
                        })();
                        {
                          const t_i5183_i12020 = $p29256_i5182_i12019._0;
                          {
                            const rng2_i5184_i12021 = $p29256_i5182_i12019._1;
                            {
                              const out_i5185_i12022 = { _0: rng2_i5184_i12021, _1: t_i5183_i12020 };
                              return out_i5185_i12022;
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const rng2 = $p28362._0;
                    {
                      const roll = $p28362._1;
                      {
                        const g2 = (() => {
                          {
                            const $t28341 = (roll < 0.25);
                            if ($t28341 === true) {
                              return (() => {
                                {
                                  const owns_starkiller = (() => {
                                    {
                                      const $t28342 = game.owned_weapons;
                                      {
                                        const $t28343 = { $: "StarKiller" };
                                        {
                                          const $t690_i4883 = { $: "$Clo_$lam689$4780", _0: $lam689$apply$4780, _1: $t28343 };
                                          return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28342, $t690_i4883);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $p28361 = (() => {
                                      {
                                        const $p29256_i5182_i12014 = (() => {
                                          {
                                            const $p15861_i12678 = (() => {
                                              {
                                                const $p15858_i1974_i12669 = Random$next_raw(rng2);
                                                {
                                                  const hi_i1975_i12670 = $p15858_i1974_i12669._0;
                                                  {
                                                    const rng2_i1976_i12671 = $p15858_i1974_i12669._1;
                                                    {
                                                      const $p15857_i1977_i12672 = Random$next_raw(rng2_i1976_i12671);
                                                      {
                                                        const lo_i1978_i12673 = $p15857_i1977_i12672._0;
                                                        {
                                                          const rng3_i1979_i12674 = $p15857_i1977_i12672._1;
                                                          {
                                                            const $t15856_i1983_i12677 = (() => {
                                                              {
                                                                const $t15855_i1982_i12676 = (() => {
                                                                  {
                                                                    const $t15853_i1980_i12675 = march_int_and(hi_i1975_i12670, 1048575);
                                                                    return ($t15853_i1980_i12675 * 4294967296);
                                                                  }
                                                                })();
                                                                return ($t15855_i1982_i12676 + lo_i1978_i12673);
                                                              }
                                                            })();
                                                            return { _0: $t15856_i1983_i12677, _1: rng3_i1979_i12674 };
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            })();
                                            {
                                              const bits_i12679 = $p15861_i12678._0;
                                              {
                                                const rng2_i12680 = $p15861_i12678._1;
                                                {
                                                  const $t15860_i12682 = (() => {
                                                    {
                                                      const $t15859_i12681 = bits_i12679;
                                                      return ($t15859_i12681 / 4.50359962737e+15);
                                                    }
                                                  })();
                                                  return { _0: $t15860_i12682, _1: rng2_i12680 };
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        {
                                          const t_i5183_i12015 = $p29256_i5182_i12014._0;
                                          {
                                            const rng2_i5184_i12016 = $p29256_i5182_i12014._1;
                                            {
                                              const out_i5185_i12017 = { _0: rng2_i5184_i12016, _1: t_i5183_i12015 };
                                              return out_i5185_i12017;
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const rng3 = $p28361._0;
                                      {
                                        const sk_roll = $p28361._1;
                                        {
                                          const $t28347 = (() => {
                                            {
                                              const $t28344 = (!owns_starkiller);
                                              {
                                                const $t28346 = (sk_roll < 0.08);
                                                return ($t28344 && $t28346);
                                              }
                                            }
                                          })();
                                          if ($t28347 === true) {
                                            return (() => {
                                              {
                                                const $t28351 = (() => {
                                                  {
                                                    const $t28350 = (() => {
                                                      {
                                                        const $t28349 = { $: "StarKiller" };
                                                        return { $: "OffenseWeapon", _0: $t28349 };
                                                      }
                                                    })();
                                                    return ({ x: sx, y: sy, ttl: 8., kind: $t28350 });
                                                  }
                                                })();
                                                {
                                                  const $t28352 = game.pickups;
                                                  {
                                                    const $t28353 = (() => {
                                                      return { $: "Cons", _0: $t28351, _1: $t28352 };
                                                    })();
                                                    return ({ ...game, rng: rng3, pickups: $t28353 });
                                                  }
                                                }
                                              }
                                            })();
                                          } else {
                                            return (() => {
                                              {
                                                const $p28360 = (() => {
                                                  {
                                                    const $t28354 = game.owned_weapons;
                                                    {
                                                      const $t28355 = game.special;
                                                      return Perihelion$Upgrades$roll_one(rng3, $t28354, $t28355);
                                                    }
                                                  }
                                                })();
                                                {
                                                  const rng4 = $p28360._0;
                                                  {
                                                    const upgrade = $p28360._1;
                                                    {
                                                      const $t28357 = (() => {
                                                        return ({ x: sx, y: sy, ttl: 8., kind: upgrade });
                                                      })();
                                                      {
                                                        const $t28358 = game.pickups;
                                                        {
                                                          const $t28359 = (() => {
                                                            return { $: "Cons", _0: $t28357, _1: $t28358 };
                                                          })();
                                                          return ({ ...game, rng: rng4, pickups: $t28359 });
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
    const $t28379 = (() => {
      {
        const $t28376 = game.pickups;
        {
          const $t28378 = { $: "$Clo_$lam28377$3736", _0: $lam28377$apply$3736, _1: game };
          return List$find$List_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float$Fn_R_kind_UpgradeKind_ttl_Float_x_Float_y_Float_Bool($t28376, $t28378);
        }
      }
    })();
    switch ($t28379.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28405 = $t28379._0;
        {
          const p = $f28405;
          {
            const $t28380 = game.pickups;
            {
              const $t28383 = { $: "$Clo_$lam28381$3737", _0: $lam28381$apply$3737, _1: game };
              {
                const remaining = (() => {
                  {
                    const pred_i4902 = $t28383;
                    {
                      const go_i4903 = { $: "$Clo_go$4749", _0: go$apply$4749, _1: pred_i4902 };
                      {
                        const $t323_i4904 = { $: "Nil" };
                        return go$apply$4749(go_i4903, $t28380, $t323_i4904);
                      }
                    }
                  }
                })();
                {
                  const $t28384 = p.kind;
                  switch ($t28384.$) {
                    case "SpecialItem": {
                      const $f28398 = $t28384._0;
                      {
                        const $jp_clo28400 = (() => {
                          return { $: "$Clo_$jp28399$3738", _0: $jp28399$apply$3738, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const $t28385 = game.special;
                          switch ($t28385.$) {
                            case "None": {
                              {
                                const $t28387 = (() => {
                                  {
                                    const $t28386 = p.kind;
                                    return Perihelion$Core$apply_upgrade(game, $t28386);
                                  }
                                })();
                                return ({ ...$t28387, pickups: remaining });
                              }
                              break;
                            }
                            case "Some": {
                              const $f28392 = $t28385._0;
                              {
                                const $t28388 = { $: "Milestone" };
                                {
                                  const $t28389 = p.kind;
                                  {
                                    const $t28390 = { $: "Nil" };
                                    {
                                      const $t28391 = (() => {
                                        return { $: "Cons", _0: $t28389, _1: $t28390 };
                                      })();
                                      return ({ ...game, pickups: remaining, phase: $t28388, milestone_choices: $t28391 });
                                    }
                                  }
                                }
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
                        const $jp_clo28404 = (() => {
                          return { $: "$Clo_$jp28403$3739", _0: $jp28403$apply$3739, _1: game, _2: p, _3: remaining };
                        })();
                        {
                          const grant = (() => {
                            {
                              const $t28393 = game.shield_reinforced;
                              if ($t28393 === true) {
                                return 2;
                              } else {
                                return 1;
                              }
                            }
                          })();
                          {
                            const $t28395 = (() => {
                              {
                                const $t28394 = game.shield;
                                return ($t28394 + grant);
                              }
                            })();
                            return ({ ...game, shield: $t28395, pickups: remaining });
                          }
                        }
                      }
                      break;
                    }
                    default: {
                      {
                        const $t28397 = (() => {
                          {
                            const $t28396 = p.kind;
                            return Perihelion$Core$apply_upgrade(game, $t28396);
                          }
                        })();
                        return ({ ...$t28397, pickups: remaining });
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
        const $t28423 = game.enemy_shots;
        {
          const $t28425 = { $: "$Clo_$lam28424$3740", _0: $lam28424$apply$3740, _1: game };
          return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28423, $t28425);
        }
      }
    })();
    {
      const $t28427 = (() => {
        {
          const $t28426 = game.bullet_ward;
          return (shot_hit && $t28426);
        }
      })();
      if ($t28427 === true) {
        return (() => {
          {
            const $t28428 = game.enemy_shots;
            {
              const $t28431 = { $: "$Clo_$lam28429$3741", _0: $lam28429$apply$3741, _1: game };
              {
                const $t28432 = (() => {
                  {
                    const pred_i4944 = $t28431;
                    {
                      const go_i4945 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4944 };
                      {
                        const $t323_i4946 = { $: "Nil" };
                        return go$apply$4753(go_i4945, $t28428, $t323_i4946);
                      }
                    }
                  }
                })();
                return ({ ...game, bullet_ward: false, enemy_shots: $t28432 });
              }
            }
          }
        })();
      } else {
        return (() => {
          {
            const ast_hit = (() => {
              {
                const $t28433 = game.asteroids;
                {
                  const $t28435 = { $: "$Clo_$lam28434$3742", _0: $lam28434$apply$3742, _1: game };
                  return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28433, $t28435);
                }
              }
            })();
            {
              const ship_hit = (() => {
                {
                  const $t28436 = game.ships;
                  {
                    const $t28438 = { $: "$Clo_$lam28437$3743", _0: $lam28437$apply$3743, _1: game };
                    return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28436, $t28438);
                  }
                }
              })();
              {
                const $t28441 = (() => {
                  {
                    const $t28440 = (() => {
                      {
                        const $t28439 = (ast_hit || shot_hit);
                        return ($t28439 || ship_hit);
                      }
                    })();
                    return (!$t28440);
                  }
                })();
                if ($t28441 === true) {
                  return game;
                } else {
                  return (() => {
                    {
                      const $t28447 = (() => {
                        {
                          const $t28445 = (() => {
                            {
                              const $t28443 = (() => {
                                {
                                  const $t28442 = (!shot_hit);
                                  return (ast_hit && $t28442);
                                }
                              })();
                              {
                                const $t28444 = (!ship_hit);
                                return ($t28443 && $t28444);
                              }
                            }
                          })();
                          {
                            const $t28446 = game.deflector_plating;
                            return ($t28445 && $t28446);
                          }
                        }
                      })();
                      if ($t28447 === true) {
                        return (() => {
                          {
                            const $p28449 = (() => {
                              {
                                const $p28422_i4939 = (() => {
                                  {
                                    const $t28420_i4938 = game.rng;
                                    {
                                      const $p29256_i12713 = (() => {
                                        {
                                          const $p15861_i5176_i12708 = (() => {
                                            {
                                              const $p15858_i12100_i12699 = Random$next_raw($t28420_i4938);
                                              {
                                                const hi_i12101_i12700 = $p15858_i12100_i12699._0;
                                                {
                                                  const rng2_i12102_i12701 = $p15858_i12100_i12699._1;
                                                  {
                                                    const $p15857_i12103_i12702 = Random$next_raw(rng2_i12102_i12701);
                                                    {
                                                      const lo_i12104_i12703 = $p15857_i12103_i12702._0;
                                                      {
                                                        const rng3_i12105_i12704 = $p15857_i12103_i12702._1;
                                                        {
                                                          const $t15856_i12109_i12707 = (() => {
                                                            {
                                                              const $t15855_i12108_i12706 = (() => {
                                                                {
                                                                  const $t15853_i12106_i12705 = march_int_and(hi_i12101_i12700, 1048575);
                                                                  return ($t15853_i12106_i12705 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15855_i12108_i12706 + lo_i12104_i12703);
                                                            }
                                                          })();
                                                          return { _0: $t15856_i12109_i12707, _1: rng3_i12105_i12704 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i5177_i12709 = $p15861_i5176_i12708._0;
                                            {
                                              const rng2_i5178_i12710 = $p15861_i5176_i12708._1;
                                              {
                                                const $t15860_i5180_i12712 = (() => {
                                                  {
                                                    const $t15859_i5179_i12711 = bits_i5177_i12709;
                                                    return ($t15859_i5179_i12711 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15860_i5180_i12712, _1: rng2_i5178_i12710 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i12714 = $p29256_i12713._0;
                                        {
                                          const rng2_i12715 = $p29256_i12713._1;
                                          {
                                            const out_i12716 = { _0: rng2_i12715, _1: t_i12714 };
                                            return out_i12716;
                                          }
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const rng2_i4940 = $p28422_i4939._0;
                                  {
                                    const t_i4941 = $p28422_i4939._1;
                                    {
                                      const $t28421_i4942 = (t_i4941 < 0.5);
                                      return { _0: rng2_i4940, _1: $t28421_i4942 };
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const rng2 = $p28449._0;
                              {
                                const deflected = $p28449._1;
                                if (deflected === true) {
                                  return ({ ...game, rng: rng2 });
                                } else {
                                  return (() => {
                                    {
                                      const $t28448 = ({ ...game, rng: rng2 });
                                      return Perihelion$Combat$collide_ball_hazards_shield_or_die($t28448);
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
    const $t28451 = (() => {
      {
        const $t28450 = game.shield;
        return ($t28450 > 0);
      }
    })();
    if ($t28451 === true) {
      return (() => {
        {
          const $t28452 = game.asteroids;
          {
            const $t28454 = { $: "$Clo_$lam28453$3744", _0: $lam28453$apply$3744, _1: game };
            {
              const dead_ast = (() => {
                {
                  const pred_i4966 = $t28454;
                  {
                    const go_i4967 = { $: "$Clo_go$4784", _0: go$apply$4784, _1: pred_i4966 };
                    {
                      const $t323_i4968 = { $: "Nil" };
                      return go$apply$4784(go_i4967, $t28452, $t323_i4968);
                    }
                  }
                }
              })();
              {
                const $t28456 = (() => {
                  {
                    const $t28455 = game.shield;
                    return ($t28455 - 1);
                  }
                })();
                {
                  const $t28457 = game.asteroids;
                  {
                    const $t28460 = { $: "$Clo_$lam28458$3745", _0: $lam28458$apply$3745, _1: game };
                    {
                      const $t28461 = (() => {
                        {
                          const pred_i4962 = $t28460;
                          {
                            const go_i4963 = { $: "$Clo_go$4784", _0: go$apply$4784, _1: pred_i4962 };
                            {
                              const $t323_i4964 = { $: "Nil" };
                              return go$apply$4784(go_i4963, $t28457, $t323_i4964);
                            }
                          }
                        }
                      })();
                      {
                        const $t28462 = game.enemy_shots;
                        {
                          const $t28465 = { $: "$Clo_$lam28463$3746", _0: $lam28463$apply$3746, _1: game };
                          {
                            const $t28466 = (() => {
                              {
                                const pred_i4958 = $t28465;
                                {
                                  const go_i4959 = { $: "$Clo_go$4753", _0: go$apply$4753, _1: pred_i4958 };
                                  {
                                    const $t323_i4960 = { $: "Nil" };
                                    return go$apply$4753(go_i4959, $t28462, $t323_i4960);
                                  }
                                }
                              }
                            })();
                            {
                              const $t28467 = game.ships;
                              {
                                const $t28470 = { $: "$Clo_$lam28468$3747", _0: $lam28468$apply$3747, _1: game };
                                {
                                  const $t28471 = (() => {
                                    {
                                      const pred_i4954 = $t28470;
                                      {
                                        const go_i4955 = { $: "$Clo_go$4765", _0: go$apply$4765, _1: pred_i4954 };
                                        {
                                          const $t323_i4956 = { $: "Nil" };
                                          return go$apply$4765(go_i4955, $t28467, $t323_i4956);
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const $t28472 = game.fx_bursts;
                                    {
                                      const $t28473 = (() => {
                                        {
                                          const $t28290_i4952 = { $: "$Clo_$lam28287$3726", _0: $lam28287$apply$3726 };
                                          {
                                            const f_i12028 = $t28290_i4952;
                                            {
                                              const go_i12029 = { $: "$Clo_go$4767", _0: go$apply$4767, _1: f_i12028 };
                                              {
                                                const $t291_i12030 = { $: "Nil" };
                                                return go$apply$4767(go_i12029, dead_ast, $t291_i12030);
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const $t28474 = (() => {
                                          {
                                            const go_i4949 = { $: "$Clo_go$4782", _0: go$apply$4782 };
                                            {
                                              const $t282_i4950 = (() => {
                                                {
                                                  const go_i12025 = { $: "$Clo_go$4327", _0: go$apply$4327 };
                                                  {
                                                    const $t274_i12026 = { $: "Nil" };
                                                    return go$apply$4327(go_i12025, $t28472, $t274_i12026);
                                                  }
                                                }
                                              })();
                                              return go$apply$4782(go_i4949, $t282_i4950, $t28473);
                                            }
                                          }
                                        })();
                                        return ({ ...game, shield: $t28456, asteroids: $t28461, enemy_shots: $t28466, ships: $t28471, fx_bursts: $t28474 });
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
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
    const $t28475 = Perihelion$Core$star_at(game, star_idx);
    switch ($t28475.$) {
      case "None": {
        return ({ ...game, rng: rng });
        break;
      }
      case "Some": {
        const $f28496 = $t28475._0;
        {
          const s = $f28496;
          {
            const $p28495 = (() => {
              {
                const $p29256_i5182_i12032 = (() => {
                  {
                    const $p15861_i12727 = (() => {
                      {
                        const $p15858_i1974_i12718 = Random$next_raw(rng);
                        {
                          const hi_i1975_i12719 = $p15858_i1974_i12718._0;
                          {
                            const rng2_i1976_i12720 = $p15858_i1974_i12718._1;
                            {
                              const $p15857_i1977_i12721 = Random$next_raw(rng2_i1976_i12720);
                              {
                                const lo_i1978_i12722 = $p15857_i1977_i12721._0;
                                {
                                  const rng3_i1979_i12723 = $p15857_i1977_i12721._1;
                                  {
                                    const $t15856_i1983_i12726 = (() => {
                                      {
                                        const $t15855_i1982_i12725 = (() => {
                                          {
                                            const $t15853_i1980_i12724 = march_int_and(hi_i1975_i12719, 1048575);
                                            return ($t15853_i1980_i12724 * 4294967296);
                                          }
                                        })();
                                        return ($t15855_i1982_i12725 + lo_i1978_i12722);
                                      }
                                    })();
                                    return { _0: $t15856_i1983_i12726, _1: rng3_i1979_i12723 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i12728 = $p15861_i12727._0;
                      {
                        const rng2_i12729 = $p15861_i12727._1;
                        {
                          const $t15860_i12731 = (() => {
                            {
                              const $t15859_i12730 = bits_i12728;
                              return ($t15859_i12730 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15860_i12731, _1: rng2_i12729 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i5183_i12033 = $p29256_i5182_i12032._0;
                  {
                    const rng2_i5184_i12034 = $p29256_i5182_i12032._1;
                    {
                      const out_i5185_i12035 = { _0: rng2_i5184_i12034, _1: t_i5183_i12033 };
                      return out_i5185_i12035;
                    }
                  }
                }
              }
            })();
            {
              const rng2 = $p28495._0;
              {
                const idle_f = $p28495._1;
                {
                  const r = (() => {
                    {
                      const $t28476 = s.capture_radius;
                      return ($t28476 * 1.6);
                    }
                  })();
                  {
                    const idle = (() => {
                      {
                        const $t28482 = (() => {
                          {
                            const $t28481 = (6. - 3.);
                            return (idle_f * $t28481);
                          }
                        })();
                        return (3. + $t28482);
                      }
                    })();
                    {
                      const ship = (() => {
                        {
                          const $t28486 = (() => {
                            {
                              const $t28483 = s.x;
                              {
                                const $t28485 = (() => {
                                  {
                                    const $t28484 = Math.cos(0.);
                                    return ($t28484 * r);
                                  }
                                })();
                                return ($t28483 + $t28485);
                              }
                            }
                          })();
                          {
                            const $t28490 = (() => {
                              {
                                const $t28487 = s.y;
                                {
                                  const $t28489 = (() => {
                                    {
                                      const $t28488 = Math.sin(0.);
                                      return ($t28488 * r);
                                    }
                                  })();
                                  return ($t28487 + $t28489);
                                }
                              }
                            })();
                            {
                              const $t28491 = { $: "ShipOrbiting", _0: 0. };
                              return ({ star_idx: star_idx, x: $t28486, y: $t28490, mode: $t28491, fire_cooldown: 2.5, idle_timer: idle, hunter: false });
                            }
                          }
                        }
                      })();
                      {
                        const $t28493 = game.ships;
                        {
                          const $t28494 = (() => {
                            return { $: "Cons", _0: ship, _1: $t28493 };
                          })();
                          return ({ ...game, rng: rng2, ships: $t28494 });
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
        const $t28498 = (() => {
          {
            const $t28497 = game.current;
            return ($t28497 > 0);
          }
        })();
        if ($t28498 === true) {
          return (() => {
            {
              const $t28499 = game.current;
              return ($t28499 - 1);
            }
          })();
        } else {
          return 0;
        }
      }
    })();
    {
      const $t28500 = Perihelion$Core$star_at(game, idx);
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
                  const $p29256_i5182_i12037 = (() => {
                    {
                      const $p15861_i12742 = (() => {
                        {
                          const $p15858_i1974_i12733 = Random$next_raw(rng);
                          {
                            const hi_i1975_i12734 = $p15858_i1974_i12733._0;
                            {
                              const rng2_i1976_i12735 = $p15858_i1974_i12733._1;
                              {
                                const $p15857_i1977_i12736 = Random$next_raw(rng2_i1976_i12735);
                                {
                                  const lo_i1978_i12737 = $p15857_i1977_i12736._0;
                                  {
                                    const rng3_i1979_i12738 = $p15857_i1977_i12736._1;
                                    {
                                      const $t15856_i1983_i12741 = (() => {
                                        {
                                          const $t15855_i1982_i12740 = (() => {
                                            {
                                              const $t15853_i1980_i12739 = march_int_and(hi_i1975_i12734, 1048575);
                                              return ($t15853_i1980_i12739 * 4294967296);
                                            }
                                          })();
                                          return ($t15855_i1982_i12740 + lo_i1978_i12737);
                                        }
                                      })();
                                      return { _0: $t15856_i1983_i12741, _1: rng3_i1979_i12738 };
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      })();
                      {
                        const bits_i12743 = $p15861_i12742._0;
                        {
                          const rng2_i12744 = $p15861_i12742._1;
                          {
                            const $t15860_i12746 = (() => {
                              {
                                const $t15859_i12745 = bits_i12743;
                                return ($t15859_i12745 / 4.50359962737e+15);
                              }
                            })();
                            return { _0: $t15860_i12746, _1: rng2_i12744 };
                          }
                        }
                      }
                    }
                  })();
                  {
                    const t_i5183_i12038 = $p29256_i5182_i12037._0;
                    {
                      const rng2_i5184_i12039 = $p29256_i5182_i12037._1;
                      {
                        const out_i5185_i12040 = { _0: rng2_i5184_i12039, _1: t_i5183_i12038 };
                        return out_i5185_i12040;
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
                                return ({ star_idx: idx, x: $t28511, y: $t28515, mode: $t28516, fire_cooldown: 2.5, idle_timer: idle, hunter: true });
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
}
const Perihelion$Combat$spawn_hunter$clo = { _0: ($_, game, rng) => Perihelion$Combat$spawn_hunter(game, rng) };

function Perihelion$Combat$maybe_spawn_ship(game, star_idx) {
  {
    const $t28524 = (() => {
      {
        const $t28522 = game.score;
        return ($t28522 < 4);
      }
    })();
    if ($t28524 === true) {
      return game;
    } else {
      return (() => {
        {
          const $p28536 = (() => {
            {
              const $t28525 = game.rng;
              {
                const $p29256_i5182_i12047 = (() => {
                  {
                    const $p15861_i12772 = (() => {
                      {
                        const $p15858_i1974_i12763 = Random$next_raw($t28525);
                        {
                          const hi_i1975_i12764 = $p15858_i1974_i12763._0;
                          {
                            const rng2_i1976_i12765 = $p15858_i1974_i12763._1;
                            {
                              const $p15857_i1977_i12766 = Random$next_raw(rng2_i1976_i12765);
                              {
                                const lo_i1978_i12767 = $p15857_i1977_i12766._0;
                                {
                                  const rng3_i1979_i12768 = $p15857_i1977_i12766._1;
                                  {
                                    const $t15856_i1983_i12771 = (() => {
                                      {
                                        const $t15855_i1982_i12770 = (() => {
                                          {
                                            const $t15853_i1980_i12769 = march_int_and(hi_i1975_i12764, 1048575);
                                            return ($t15853_i1980_i12769 * 4294967296);
                                          }
                                        })();
                                        return ($t15855_i1982_i12770 + lo_i1978_i12767);
                                      }
                                    })();
                                    return { _0: $t15856_i1983_i12771, _1: rng3_i1979_i12768 };
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    })();
                    {
                      const bits_i12773 = $p15861_i12772._0;
                      {
                        const rng2_i12774 = $p15861_i12772._1;
                        {
                          const $t15860_i12776 = (() => {
                            {
                              const $t15859_i12775 = bits_i12773;
                              return ($t15859_i12775 / 4.50359962737e+15);
                            }
                          })();
                          return { _0: $t15860_i12776, _1: rng2_i12774 };
                        }
                      }
                    }
                  }
                })();
                {
                  const t_i5183_i12048 = $p29256_i5182_i12047._0;
                  {
                    const rng2_i5184_i12049 = $p29256_i5182_i12047._1;
                    {
                      const out_i5185_i12050 = { _0: rng2_i5184_i12049, _1: t_i5183_i12048 };
                      return out_i5185_i12050;
                    }
                  }
                }
              }
            }
          })();
          {
            const rng2 = $p28536._0;
            {
              const roll = $p28536._1;
              {
                const chance_raw = (() => {
                  {
                    const $t28530 = (() => {
                      {
                        const $t28529 = (() => {
                          {
                            const $t28528 = (() => {
                              {
                                const $t28526 = game.score;
                                return ($t28526 - 4);
                              }
                            })();
                            return $t28528;
                          }
                        })();
                        return (0.04 * $t28529);
                      }
                    })();
                    return (0.16 + $t28530);
                  }
                })();
                {
                  const chance = (() => {
                    {
                      const $t28531 = (chance_raw > 0.45);
                      if ($t28531 === true) {
                        return 0.45;
                      } else {
                        return chance_raw;
                      }
                    }
                  })();
                  {
                    const $t28532 = (roll < chance);
                    if ($t28532 === true) {
                      return (() => {
                        {
                          const $p28535 = (() => {
                            {
                              const $p29256_i5182_i12042 = (() => {
                                {
                                  const $p15861_i12757 = (() => {
                                    {
                                      const $p15858_i1974_i12748 = Random$next_raw(rng2);
                                      {
                                        const hi_i1975_i12749 = $p15858_i1974_i12748._0;
                                        {
                                          const rng2_i1976_i12750 = $p15858_i1974_i12748._1;
                                          {
                                            const $p15857_i1977_i12751 = Random$next_raw(rng2_i1976_i12750);
                                            {
                                              const lo_i1978_i12752 = $p15857_i1977_i12751._0;
                                              {
                                                const rng3_i1979_i12753 = $p15857_i1977_i12751._1;
                                                {
                                                  const $t15856_i1983_i12756 = (() => {
                                                    {
                                                      const $t15855_i1982_i12755 = (() => {
                                                        {
                                                          const $t15853_i1980_i12754 = march_int_and(hi_i1975_i12749, 1048575);
                                                          return ($t15853_i1980_i12754 * 4294967296);
                                                        }
                                                      })();
                                                      return ($t15855_i1982_i12755 + lo_i1978_i12752);
                                                    }
                                                  })();
                                                  return { _0: $t15856_i1983_i12756, _1: rng3_i1979_i12753 };
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const bits_i12758 = $p15861_i12757._0;
                                    {
                                      const rng2_i12759 = $p15861_i12757._1;
                                      {
                                        const $t15860_i12761 = (() => {
                                          {
                                            const $t15859_i12760 = bits_i12758;
                                            return ($t15859_i12760 / 4.50359962737e+15);
                                          }
                                        })();
                                        return { _0: $t15860_i12761, _1: rng2_i12759 };
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const t_i5183_i12043 = $p29256_i5182_i12042._0;
                                {
                                  const rng2_i5184_i12044 = $p29256_i5182_i12042._1;
                                  {
                                    const out_i5185_i12045 = { _0: rng2_i5184_i12044, _1: t_i5183_i12043 };
                                    return out_i5185_i12045;
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const rng3 = $p28535._0;
                            {
                              const kind_roll = $p28535._1;
                              {
                                const $t28534 = (kind_roll < 0.5);
                                if ($t28534 === true) {
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
    const $t28537 = game.stars;
    return List$nth_opt$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int($t28537, i);
  }
}
const Perihelion$Core$star_at$clo = { _0: ($_, game, i) => Perihelion$Core$star_at(game, i) };

function Perihelion$Core$remove_at(xs, idx) {
  {
    const $t28538 = (() => {
      {
        const go_i4985 = { $: "$Clo_go$4790", _0: go$apply$4790 };
        {
          const $t529_i4986 = { $: "Nil" };
          return go$apply$4790(go_i4985, xs, idx, $t529_i4986);
        }
      }
    })();
    {
      const $t28539 = (idx + 1);
      {
        const $t28540 = List$drop$List_R_capture_radius_Float_orbits_List_R_radius_Float_speed_mult_Float_radius_Float_speed_mult_Float_x_Float_y_Float$Int(xs, $t28539);
        {
          const go_i4981 = { $: "$Clo_go$4787", _0: go$apply$4787 };
          {
            const $t282_i4982 = (() => {
              {
                const go_i12052 = { $: "$Clo_go$5259", _0: go$apply$5259 };
                {
                  const $t274_i12053 = { $: "Nil" };
                  return go$apply$5259(go_i12052, $t28538, $t274_i12053);
                }
              }
            })();
            return go$apply$4787(go_i4981, $t282_i4982, $t28540);
          }
        }
      }
    }
  }
}
const Perihelion$Core$remove_at$clo = { _0: ($_, xs, idx) => Perihelion$Core$remove_at(xs, idx) };

function Perihelion$Core$remove_star(game, idx) {
  {
    const $t28541 = game.stars;
    {
      const $t28542 = (() => {
        return Perihelion$Core$remove_at($t28541, idx);
      })();
      return ({ ...game, stars: $t28542 });
    }
  }
}
const Perihelion$Core$remove_star$clo = { _0: ($_, game, idx) => Perihelion$Core$remove_star(game, idx) };

function Perihelion$Core$ring_count(s) {
  {
    const $t28543 = s.orbits;
    {
      const go_i4988 = { $: "$Clo_go$4792", _0: go$apply$4792 };
      return go$apply$4792(go_i4988, $t28543, 0);
    }
  }
}
const Perihelion$Core$ring_count$clo = { _0: ($_, s) => Perihelion$Core$ring_count(s) };

function Perihelion$Core$ring_at(s, i) {
  {
    const $t28545 = (() => {
      {
        const $t28544 = s.orbits;
        return List$nth_opt$List_R_radius_Float_speed_mult_Float$Int($t28544, i);
      }
    })();
    switch ($t28545.$) {
      case "Some": {
        const $f28548 = $t28545._0;
        {
          const o = $f28548;
          return o;
        }
        break;
      }
      case "None": {
        {
          const $t28546 = s.capture_radius;
          {
            const $t28547 = s.speed_mult;
            return ({ radius: $t28546, speed_mult: $t28547 });
          }
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
        const $t28553 = { $: "$Clo_$lam28550$3748", _0: $lam28550$apply$3748 };
        return List$any$List_String$Fn_String_Bool(keys, $t28553);
      }
    })();
    {
      const inn = (() => {
        {
          const $t28557 = { $: "$Clo_$lam28554$3749", _0: $lam28554$apply$3749 };
          return List$any$List_String$Fn_String_Bool(keys, $t28557);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28558;
            if (out === true) {
              $t28558 = 1;
            } else {
              $t28558 = 0;
            }
            {
              let $t28559;
              if (inn === true) {
                $t28559 = 1;
              } else {
                $t28559 = 0;
              }
              return ($t28558 - $t28559);
            }
          }
        })();
        {
          const target = (ring_idx + delta);
          {
            const $t28560 = (target < 0);
            if ($t28560 === true) {
              return 0;
            } else {
              return (() => {
                {
                  const $t28562 = (() => {
                    {
                      const $t28561 = (n - 1);
                      return (target > $t28561);
                    }
                  })();
                  if ($t28562 === true) {
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
        const $t28563 = game.owned_weapons;
        {
          const go_i4992 = { $: "$Clo_go$4796", _0: go$apply$4796 };
          return go$apply$4796(go_i4992, $t28563, 0);
        }
      }
    })();
    {
      const idx = (() => {
        {
          const $t28565 = (() => {
            {
              const $t28564 = game.active_weapon_idx;
              return ($t28564 >= n);
            }
          })();
          if ($t28565 === true) {
            return 0;
          } else {
            return game.active_weapon_idx;
          }
        }
      })();
      {
        const $t28567 = (() => {
          {
            const $t28566 = game.owned_weapons;
            return List$nth_opt$List_WeaponKind$Int($t28566, idx);
          }
        })();
        switch ($t28567.$) {
          case "Some": {
            const $f28568 = $t28567._0;
            {
              const w = $f28568;
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
        const $t28572 = { $: "$Clo_$lam28569$3750", _0: $lam28569$apply$3750 };
        return List$any$List_String$Fn_String_Bool(keys, $t28572);
      }
    })();
    {
      const prev = (() => {
        {
          const $t28576 = { $: "$Clo_$lam28573$3751", _0: $lam28573$apply$3751 };
          return List$any$List_String$Fn_String_Bool(keys, $t28576);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28577;
            if (next === true) {
              $t28577 = 1;
            } else {
              $t28577 = 0;
            }
            {
              let $t28578;
              if (prev === true) {
                $t28578 = 1;
              } else {
                $t28578 = 0;
              }
              return ($t28577 - $t28578);
            }
          }
        })();
        {
          const raw = (() => {
            {
              const $t28579 = (idx + delta);
              return march_int_mod($t28579, n);
            }
          })();
          {
            const $t28580 = (raw < 0);
            if ($t28580 === true) {
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
        const $t28584 = { $: "$Clo_$lam28581$3752", _0: $lam28581$apply$3752 };
        return List$any$List_String$Fn_String_Bool(keys, $t28584);
      }
    })();
    {
      const up = (() => {
        {
          const $t28588 = { $: "$Clo_$lam28585$3753", _0: $lam28585$apply$3753 };
          return List$any$List_String$Fn_String_Bool(keys, $t28588);
        }
      })();
      {
        const delta = (() => {
          {
            let $t28589;
            if (dn === true) {
              $t28589 = 1;
            } else {
              $t28589 = 0;
            }
            {
              let $t28590;
              if (up === true) {
                $t28590 = 1;
              } else {
                $t28590 = 0;
              }
              return ($t28589 - $t28590);
            }
          }
        })();
        {
          const $t28592 = (() => {
            {
              const $t28591 = (offset + delta);
              return ($t28591 + 3);
            }
          })();
          return march_int_mod($t28592, 3);
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
            const $t28595 = best.x;
            {
              const $t28596 = game.ball_x;
              return ($t28595 - $t28596);
            }
          }
        })();
        {
          const dy = (() => {
            {
              const $t28597 = best.y;
              {
                const $t28598 = game.ball_y;
                return ($t28597 - $t28598);
              }
            }
          })();
          {
            const d = Math.sqrt(best_d2);
            {
              const $t28599 = (d > 0.);
              if ($t28599 === true) {
                return (() => {
                  {
                    const $t28600 = (dx / d);
                    {
                      const $t28601 = (dy / d);
                      {
                        const $t28602 = { _0: $t28600, _1: $t28601 };
                        return { $: "Some", _0: $t28602 };
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
      const $f28608 = stars._0;
      const $f28609 = stars._1;
      {
        const rest = (() => {
          return $f28609;
        })();
        {
          const s = (() => {
            return $f28608;
          })();
          {
            const d2 = (() => {
              {
                const $t28603 = game.ball_x;
                {
                  const $t28604 = game.ball_y;
                  {
                    const $t28605 = s.x;
                    {
                      const $t28606 = s.y;
                      {
                        const dx_i4999 = ($t28603 - $t28605);
                        {
                          const dy_i5000 = ($t28604 - $t28606);
                          {
                            const $t28593_i5001 = (dx_i4999 * dx_i4999);
                            {
                              const $t28594_i5002 = (dy_i5000 * dy_i5000);
                              return ($t28593_i5001 + $t28594_i5002);
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
              const $t28607 = (d2 < best_d2);
              if ($t28607 === true) {
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
    const $t28614 = game.stars;
    switch ($t28614.$) {
      case "Nil": {
        return { $: "None" };
        break;
      }
      case "Cons": {
        const $f28620 = $t28614._0;
        const $f28621 = $t28614._1;
        {
          const rest = (() => {
            return $f28621;
          })();
          {
            const s0 = (() => {
              return $f28620;
            })();
            {
              const $t28619 = (() => {
                {
                  const $t28615 = game.ball_x;
                  {
                    const $t28616 = game.ball_y;
                    {
                      const $t28617 = s0.x;
                      {
                        const $t28618 = s0.y;
                        {
                          const dx_i5008 = ($t28615 - $t28617);
                          {
                            const dy_i5009 = ($t28616 - $t28618);
                            {
                              const $t28593_i5010 = (dx_i5008 * dx_i5008);
                              {
                                const $t28594_i5011 = (dy_i5009 * dy_i5009);
                                return ($t28593_i5010 + $t28594_i5011);
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
                const $rc_615 = Perihelion$Core$nearest_star_dir_go(game, rest, s0, $t28619);
                return $rc_615;
              }
            }
          }
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
    const $p28637 = (() => {
      {
        const $t28626 = game.rng;
        {
          const $p29256_i12060 = (() => {
            {
              const $p15861_i5176_i12055 = (() => {
                {
                  const $p15858_i12778 = Random$next_raw($t28626);
                  {
                    const hi_i12779 = $p15858_i12778._0;
                    {
                      const rng2_i12780 = $p15858_i12778._1;
                      {
                        const $p15857_i12781 = Random$next_raw(rng2_i12780);
                        {
                          const lo_i12782 = $p15857_i12781._0;
                          {
                            const rng3_i12783 = $p15857_i12781._1;
                            {
                              const $t15856_i12786 = (() => {
                                {
                                  const $t15855_i12785 = (() => {
                                    {
                                      const $t15853_i12784 = march_int_and(hi_i12779, 1048575);
                                      return ($t15853_i12784 * 4294967296);
                                    }
                                  })();
                                  return ($t15855_i12785 + lo_i12782);
                                }
                              })();
                              return { _0: $t15856_i12786, _1: rng3_i12783 };
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })();
              {
                const bits_i5177_i12056 = $p15861_i5176_i12055._0;
                {
                  const rng2_i5178_i12057 = $p15861_i5176_i12055._1;
                  {
                    const $t15860_i5180_i12059 = (() => {
                      {
                        const $t15859_i5179_i12058 = bits_i5177_i12056;
                        return ($t15859_i5179_i12058 / 4.50359962737e+15);
                      }
                    })();
                    return { _0: $t15860_i5180_i12059, _1: rng2_i5178_i12057 };
                  }
                }
              }
            }
          })();
          {
            const t_i12061 = $p29256_i12060._0;
            {
              const rng2_i12062 = $p29256_i12060._1;
              {
                const out_i12063 = { _0: rng2_i12062, _1: t_i12061 };
                return out_i12063;
              }
            }
          }
        }
      }
    })();
    {
      const rng2 = $p28637._0;
      {
        const t = $p28637._1;
        {
          const jump = (() => {
            {
              const $t28630 = (() => {
                {
                  const $t28629 = (t * 4.);
                  return Math.trunc($t28629);
                }
              })();
              return (1 + $t28630);
            }
          })();
          {
            const target_idx = (() => {
              {
                const $t28631 = game.current;
                return ($t28631 + jump);
              }
            })();
            {
              const $t28632 = Perihelion$Core$star_at(game, target_idx);
              switch ($t28632.$) {
                case "None": {
                  return ({ ...game, rng: rng2 });
                  break;
                }
                case "Some": {
                  const $f28636 = $t28632._0;
                  {
                    const target = $f28636;
                    {
                      const $t28635 = (() => {
                        {
                          const $t28634 = (() => {
                            {
                              const $t28633 = game.special_charges;
                              return ($t28633 - 1);
                            }
                          })();
                          return ({ ...game, rng: rng2, special_charges: $t28634 });
                        }
                      })();
                      return Perihelion$Core$on_capture($t28635, target, target_idx);
                    }
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
        const $t28641 = { $: "$Clo_$lam28638$3756", _0: $lam28638$apply$3756 };
        return List$any$List_String$Fn_String_Bool(keys, $t28641);
      }
    })();
    {
      const $t28645 = (() => {
        {
          const $t28642 = (!pressed);
          {
            const $t28644 = (() => {
              {
                const $t28643 = game.special_charges;
                return ($t28643 <= 0);
              }
            })();
            return ($t28642 || $t28644);
          }
        }
      })();
      if ($t28645 === true) {
        return game;
      } else {
        return (() => {
          {
            const $t28646 = game.special;
            switch ($t28646.$) {
              case "None": {
                return game;
                break;
              }
              case "Some": {
                const $f28677 = $t28646._0;
                switch ($f28677.$) {
                  case "StarThrust": {
                    {
                      const $t28647 = Perihelion$Core$nearest_star_dir(game);
                      switch ($t28647.$) {
                        case "None": {
                          return game;
                          break;
                        }
                        case "Some": {
                          const $f28676 = $t28647._0;
                          {
                            const pair = $f28676;
                            {
                              const dx = pair._0;
                              {
                                const dy = pair._1;
                                {
                                  const $t28648 = game.mode;
                                  switch ($t28648.$) {
                                    case "Flying": {
                                      const $f28658 = $t28648._0;
                                      const $f28659 = $t28648._1;
                                      {
                                        const vy = (() => {
                                          return $f28659;
                                        })();
                                        {
                                          const vx = (() => {
                                            return $f28658;
                                          })();
                                          {
                                            const $t28655 = (() => {
                                              {
                                                const $t28651 = (() => {
                                                  {
                                                    const $t28650 = (dx * 60.);
                                                    return (vx + $t28650);
                                                  }
                                                })();
                                                {
                                                  const $t28654 = (() => {
                                                    {
                                                      const $t28653 = (dy * 60.);
                                                      return (vy + $t28653);
                                                    }
                                                  })();
                                                  return { $: "Flying", _0: $t28651, _1: $t28654 };
                                                }
                                              }
                                            })();
                                            {
                                              const $t28657 = (() => {
                                                {
                                                  const $t28656 = game.special_charges;
                                                  return ($t28656 - 1);
                                                }
                                              })();
                                              return ({ ...game, mode: $t28655, special_charges: $t28657 });
                                            }
                                          }
                                        }
                                      }
                                      break;
                                    }
                                    case "Orbiting": {
                                      const $f28664 = $t28648._0;
                                      const $f28665 = $t28648._1;
                                      const $f28666 = $t28648._2;
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
        const $t28682 = { $: "Nil" };
        {
          const $t28683 = { $: "None" };
          return ({ ...game, view_w: view_w, view_h: view_h, fx_bursts: $t28682, capture_flash: $t28683 });
        }
      }
    })();
    {
      const $t28684 = (() => {
        {
          const $t28681_i5022 = { $: "$Clo_$lam28678$3761", _0: $lam28678$apply$3761 };
          return List$any$List_String$Fn_String_Bool(keys, $t28681_i5022);
        }
      })();
      if ($t28684 === true) {
        return Perihelion$Core$reset(g0);
      } else {
        return (() => {
          {
            const tapped = (() => {
              {
                let $t28685;
                switch (taps.$) {
                  case "Nil": {
                    $t28685 = true;
                    break;
                  }
                  default: {
                    $t28685 = false;
                    break;
                  }
                }
                return (!$t28685);
              }
            })();
            {
              const $t28686 = g0.phase;
              switch ($t28686.$) {
                case "Ready": {
                  if (tapped === true) {
                    return (() => {
                      {
                        const $t28687 = { $: "Playing" };
                        return ({ ...g0, phase: $t28687 });
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
                        const $t28689 = (() => {
                          {
                            const $t28688 = g0.milestone_choices;
                            return List$nth_opt$List_UpgradeKind$Int($t28688, 0);
                          }
                        })();
                        switch ($t28689.$) {
                          case "None": {
                            return g0;
                            break;
                          }
                          case "Some": {
                            const $f28694 = $t28689._0;
                            {
                              const choice = $f28694;
                              {
                                const $t28693 = (() => {
                                  {
                                    const $t28690 = Perihelion$Core$apply_upgrade(g0, choice);
                                    {
                                      const $t28691 = { $: "Playing" };
                                      {
                                        const $t28692 = { $: "Nil" };
                                        return ({ ...$t28690, phase: $t28691, milestone_choices: $t28692 });
                                      }
                                    }
                                  }
                                })();
                                return Perihelion$Core$top_up($t28693);
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
        const $t28695 = game.mode;
        switch ($t28695.$) {
          case "Orbiting": {
            const $f28696 = $t28695._0;
            const $f28697 = $t28695._1;
            const $f28698 = $t28695._2;
            {
              const angle = (() => {
                return $f28698;
              })();
              {
                const ring = (() => {
                  return $f28697;
                })();
                {
                  const idx = (() => {
                    return $f28696;
                  })();
                  return Perihelion$Core$step_orbit(game, idx, ring, angle, tapped, keys, dt_s);
                }
              }
            }
            break;
          }
          case "Flying": {
            const $f28707 = $t28695._0;
            const $f28708 = $t28695._1;
            {
              const vy = (() => {
                return $f28708;
              })();
              {
                const vx = (() => {
                  return $f28707;
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
          const $t28713 = g0.owned_weapons;
          {
            const go_i5033 = { $: "$Clo_go$4796", _0: go$apply$4796 };
            return go$apply$4796(go_i5033, $t28713, 0);
          }
        }
      })();
      {
        const g1a = (() => {
          {
            const $t28715 = (() => {
              {
                const $t28714 = g0.active_weapon_idx;
                return Perihelion$Core$adjust_weapon($t28714, keys, n);
              }
            })();
            return ({ ...g0, active_weapon_idx: $t28715 });
          }
        })();
        {
          const g1 = (() => {
            {
              const $t28717 = (() => {
                {
                  const $t28716 = g1a.starkiller_target_offset;
                  return Perihelion$Core$adjust_starkiller_target($t28716, keys);
                }
              })();
              return ({ ...g1a, starkiller_target_offset: $t28717 });
            }
          })();
          {
            const g1x = (() => {
              return Perihelion$Core$apply_special(g1, keys);
            })();
            {
              const $t28718 = g1x.phase;
              switch ($t28718.$) {
                case "Playing": {
                  {
                    const g2 = (() => {
                      {
                        const g1_i5030 = Perihelion$Combat$step_spawn(g1x, dt_s);
                        {
                          const g2_i5031 = Perihelion$Combat$step_entities(g1_i5030, dt_s);
                          return Perihelion$Combat$step_ships(g2_i5031, dt_s);
                        }
                      }
                    })();
                    {
                      const g3 = Perihelion$Combat$fire(g2, keys, cursor, dt_s);
                      {
                        const g4 = (() => {
                          {
                            const g0_i5024 = Perihelion$Combat$collide_shots_stars(g3);
                            {
                              const g1_i5025 = Perihelion$Combat$collide_shots_asteroids(g0_i5024);
                              {
                                const g2_i5026 = Perihelion$Combat$collide_shots_ships(g1_i5025);
                                {
                                  const g3_i5027 = Perihelion$Combat$collide_ball_pickups(g2_i5026);
                                  return Perihelion$Combat$collide_ball_hazards(g3_i5027);
                                }
                              }
                            }
                          }
                        })();
                        {
                          const $t28719 = (() => {
                            return g4.phase;
                          })();
                          switch ($t28719.$) {
                            case "Playing": {
                              {
                                const $t28720 = (() => {
                                  {
                                    const $rc_616 = Perihelion$Core$step_camera(g4, dt_s);
                                    return $rc_616;
                                  }
                                })();
                                return Perihelion$Core$top_up($t28720);
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
    const $t28721 = Perihelion$Core$star_at(game, idx);
    switch ($t28721.$) {
      case "None": {
        return game;
        break;
      }
      case "Some": {
        const $f28744 = $t28721._0;
        {
          const s = $f28744;
          if (tapped === true) {
            return (() => {
              {
                const vx_i5047 = (() => {
                  {
                    const $t28748_i5046 = (() => {
                      {
                        const $t28746_i5044 = (1. * 340.);
                        {
                          const $t28747_i5045 = Math.sin(angle);
                          return ($t28746_i5044 * $t28747_i5045);
                        }
                      }
                    })();
                    return (0. - $t28748_i5046);
                  }
                })();
                {
                  const vy_i5051 = (() => {
                    {
                      const $t28750_i5049 = (1. * 340.);
                      {
                        const $t28751_i5050 = Math.cos(angle);
                        return ($t28750_i5049 * $t28751_i5050);
                      }
                    }
                  })();
                  {
                    const $t28752_i5052 = { $: "Flying", _0: vx_i5047, _1: vy_i5051 };
                    return ({ ...game, mode: $t28752_i5052 });
                  }
                }
              }
            })();
          } else {
            return (() => {
              {
                const ring2 = (() => {
                  {
                    const $t28722 = Perihelion$Core$ring_count(s);
                    return Perihelion$Core$adjust_ring(ring, keys, $t28722);
                  }
                })();
                {
                  const o = Perihelion$Core$ring_at(s, ring2);
                  {
                    const a2 = (() => {
                      {
                        const $t28728 = (() => {
                          {
                            const $t28727 = (() => {
                              {
                                const $t28725 = (1. * 1.8);
                                {
                                  const $t28726 = o.speed_mult;
                                  return ($t28725 * $t28726);
                                }
                              }
                            })();
                            return ($t28727 * dt_s);
                          }
                        })();
                        return (angle + $t28728);
                      }
                    })();
                    {
                      const r = o.radius;
                      {
                        const $t28729 = { $: "Orbiting", _0: idx, _1: ring2, _2: a2 };
                        {
                          const $t28735 = (() => {
                            {
                              const $t28730 = game.loop_angle;
                              {
                                const $t28734 = (() => {
                                  {
                                    const $t28733 = (() => {
                                      {
                                        const $t28732 = o.speed_mult;
                                        return (1.8 * $t28732);
                                      }
                                    })();
                                    return ($t28733 * dt_s);
                                  }
                                })();
                                return ($t28730 + $t28734);
                              }
                            }
                          })();
                          {
                            const $t28739 = (() => {
                              {
                                const $t28736 = s.x;
                                {
                                  const $t28738 = (() => {
                                    {
                                      const $t28737 = Math.cos(a2);
                                      return ($t28737 * r);
                                    }
                                  })();
                                  return ($t28736 + $t28738);
                                }
                              }
                            })();
                            {
                              const $t28743 = (() => {
                                {
                                  const $t28740 = s.y;
                                  {
                                    const $t28742 = (() => {
                                      {
                                        const $t28741 = Math.sin(a2);
                                        return ($t28741 * r);
                                      }
                                    })();
                                    return ($t28740 + $t28742);
                                  }
                                }
                              })();
                              return ({ ...game, mode: $t28729, loop_angle: $t28735, ball_x: $t28739, ball_y: $t28743 });
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
        const $t28755 = (() => {
          {
            const $t28753 = (vx * vx);
            {
              const $t28754 = (vy * vy);
              return ($t28753 + $t28754);
            }
          }
        })();
        return Math.sqrt($t28755);
      }
    })();
    {
      const $t28756 = (m > 0.);
      if ($t28756 === true) {
        return (() => {
          {
            const out = (() => {
              {
                const $t28759 = (() => {
                  {
                    const $t28757 = (vx / m);
                    return ($t28757 * 340.);
                  }
                })();
                {
                  const $t28762 = (() => {
                    {
                      const $t28760 = (vy / m);
                      return ($t28760 * 340.);
                    }
                  })();
                  return { _0: $t28759, _1: $t28762 };
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
      const $f28781 = stars._0;
      const $f28782 = stars._1;
      {
        const rest = $f28782;
        {
          const s = $f28781;
          {
            const dx = (() => {
              {
                const $t28763 = s.x;
                {
                  const $t28764 = game.ball_x;
                  return ($t28763 - $t28764);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28765 = s.y;
                  {
                    const $t28766 = game.ball_y;
                    return ($t28765 - $t28766);
                  }
                }
              })();
              {
                const d = (() => {
                  {
                    const $t28769 = (() => {
                      {
                        const $t28767 = (dx * dx);
                        {
                          const $t28768 = (dy * dy);
                          return ($t28767 + $t28768);
                        }
                      }
                    })();
                    return Math.sqrt($t28769);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28772 = (() => {
                        {
                          const $t28770 = (vx * dx);
                          {
                            const $t28771 = (vy * dy);
                            return ($t28770 + $t28771);
                          }
                        }
                      })();
                      return ($t28772 > 0.);
                    }
                  })();
                  {
                    const $t28779 = (() => {
                      {
                        const $t28777 = (() => {
                          {
                            const $t28776 = (() => {
                              {
                                const $t28775 = (() => {
                                  {
                                    const $t28774 = s.capture_radius;
                                    return (2.4 * $t28774);
                                  }
                                })();
                                return (d < $t28775);
                              }
                            })();
                            return (approaching && $t28776);
                          }
                        })();
                        {
                          const $t28778 = (d < best_d);
                          return ($t28777 && $t28778);
                        }
                      }
                    })();
                    if ($t28779 === true) {
                      return (() => {
                        {
                          const $t28780 = { $: "Some", _0: s };
                          return Perihelion$Core$nearest_assist_target(game, vx, vy, rest, $t28780, d);
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
    const $t28789 = (() => {
      {
        const $t28787 = game.stars;
        {
          const $t28788 = { $: "None" };
          return Perihelion$Core$nearest_assist_target(game, vx, vy, $t28787, $t28788, 999999.);
        }
      }
    })();
    switch ($t28789.$) {
      case "None": {
        {
          const out = { _0: vx, _1: vy };
          return out;
        }
        break;
      }
      case "Some": {
        const $f28808 = $t28789._0;
        {
          const t = $f28808;
          {
            const dx = (() => {
              {
                const $t28790 = t.x;
                {
                  const $t28791 = game.ball_x;
                  return ($t28790 - $t28791);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28792 = t.y;
                  {
                    const $t28793 = game.ball_y;
                    return ($t28792 - $t28793);
                  }
                }
              })();
              {
                const dist = (() => {
                  {
                    const $t28796 = (() => {
                      {
                        const $t28794 = (dx * dx);
                        {
                          const $t28795 = (dy * dy);
                          return ($t28794 + $t28795);
                        }
                      }
                    })();
                    return Math.sqrt($t28796);
                  }
                })();
                {
                  const $t28797 = (dist > 0.);
                  if ($t28797 === true) {
                    return (() => {
                      {
                        const $t28802 = (() => {
                          {
                            const $t28801 = (() => {
                              {
                                const $t28800 = (() => {
                                  {
                                    const $t28798 = (dx / dist);
                                    return ($t28798 * 1600.);
                                  }
                                })();
                                return ($t28800 * dt_s);
                              }
                            })();
                            return (vx + $t28801);
                          }
                        })();
                        {
                          const $t28807 = (() => {
                            {
                              const $t28806 = (() => {
                                {
                                  const $t28805 = (() => {
                                    {
                                      const $t28803 = (dy / dist);
                                      return ($t28803 * 1600.);
                                    }
                                  })();
                                  return ($t28805 * dt_s);
                                }
                              })();
                              return (vy + $t28806);
                            }
                          })();
                          return Perihelion$Core$renormalize($t28802, $t28807);
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
    const $t28809 = (n === 0);
    if ($t28809 === true) {
      return (() => {
        {
          const go_i5062 = { $: "$Clo_go$4327", _0: go$apply$4327 };
          {
            const $t274_i5063 = { $: "Nil" };
            return go$apply$4327(go_i5062, acc, $t274_i5063);
          }
        }
      })();
    } else {
      return (() => {
        {
          const simmed = ({ ...game, ball_x: x, ball_y: y });
          {
            const $p28818 = Perihelion$Core$assisted_velocity(simmed, vx, vy, 0.05);
            {
              const vx2 = $p28818._0;
              {
                const vy2 = $p28818._1;
                {
                  const x2 = (() => {
                    {
                      const $t28812 = (vx2 * 0.05);
                      return (x + $t28812);
                    }
                  })();
                  {
                    const y2 = (() => {
                      {
                        const $t28814 = (vy2 * 0.05);
                        return (y + $t28814);
                      }
                    })();
                    {
                      const $t28815 = (n - 1);
                      {
                        const $t28816 = { _0: x2, _1: y2 };
                        {
                          const $t28817 = { $: "Cons", _0: $t28816, _1: acc };
                          return Perihelion$Core$predict_trajectory_go(game, x2, y2, vx2, vy2, $t28815, $t28817);
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
    const $t28819 = Perihelion$Core$star_at(game, idx);
    switch ($t28819.$) {
      case "None": {
        return { $: "Nil" };
        break;
      }
      case "Some": {
        const $f28849 = $t28819._0;
        {
          const s = $f28849;
          {
            const o = Perihelion$Core$ring_at(s, ring);
            {
              const start_x = (() => {
                {
                  const $t28820 = s.x;
                  {
                    const $t28823 = (() => {
                      {
                        const $t28821 = Math.cos(angle);
                        {
                          const $t28822 = o.radius;
                          return ($t28821 * $t28822);
                        }
                      }
                    })();
                    return ($t28820 + $t28823);
                  }
                }
              })();
              {
                const start_y = (() => {
                  {
                    const $t28824 = s.y;
                    {
                      const $t28827 = (() => {
                        {
                          const $t28825 = Math.sin(angle);
                          {
                            const $t28826 = o.radius;
                            return ($t28825 * $t28826);
                          }
                        }
                      })();
                      return ($t28824 + $t28827);
                    }
                  }
                })();
                {
                  const $t28829 = (() => {
                    {
                      const $t28828 = (() => {
                        {
                          const vx_i5074 = (() => {
                            {
                              const $t28748_i5073 = (() => {
                                {
                                  const $t28746_i5071 = (1. * 340.);
                                  {
                                    const $t28747_i5072 = Math.sin(angle);
                                    return ($t28746_i5071 * $t28747_i5072);
                                  }
                                }
                              })();
                              return (0. - $t28748_i5073);
                            }
                          })();
                          {
                            const vy_i5078 = (() => {
                              {
                                const $t28750_i5076 = (1. * 340.);
                                {
                                  const $t28751_i5077 = Math.cos(angle);
                                  return ($t28750_i5076 * $t28751_i5077);
                                }
                              }
                            })();
                            {
                              const $t28752_i5079 = { $: "Flying", _0: vx_i5074, _1: vy_i5078 };
                              return ({ ...game, mode: $t28752_i5079 });
                            }
                          }
                        }
                      })();
                      return $t28828.mode;
                    }
                  })();
                  switch ($t28829.$) {
                    case "Flying": {
                      const $f28832 = $t28829._0;
                      const $f28833 = $t28829._1;
                      {
                        const vy0 = $f28833;
                        {
                          const vx0 = $f28832;
                          {
                            const $t28831 = { $: "Nil" };
                            return Perihelion$Core$predict_trajectory_go(game, start_x, start_y, vx0, vy0, 24, $t28831);
                          }
                        }
                      }
                      break;
                    }
                    case "Orbiting": {
                      const $f28838 = $t28829._0;
                      const $f28839 = $t28829._1;
                      const $f28840 = $t28829._2;
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
      const $f28870 = stars._0;
      const $f28871 = stars._1;
      {
        const rest = $f28871;
        {
          const s = $f28870;
          {
            const dx = (() => {
              {
                const $t28850 = s.x;
                {
                  const $t28851 = game.ball_x;
                  return ($t28850 - $t28851);
                }
              }
            })();
            {
              const dy = (() => {
                {
                  const $t28852 = s.y;
                  {
                    const $t28853 = game.ball_y;
                    return ($t28852 - $t28853);
                  }
                }
              })();
              {
                const grace = (() => {
                  {
                    const $t28854 = s.capture_radius;
                    return ($t28854 + 6.);
                  }
                })();
                {
                  const approaching = (() => {
                    {
                      const $t28858 = (() => {
                        {
                          const $t28856 = (vx * dx);
                          {
                            const $t28857 = (vy * dy);
                            return ($t28856 + $t28857);
                          }
                        }
                      })();
                      return ($t28858 > 0.);
                    }
                  })();
                  {
                    const $t28867 = (() => {
                      {
                        const $t28861 = (() => {
                          {
                            const $t28860 = (() => {
                              {
                                const $t28859 = game.current;
                                return (i !== $t28859);
                              }
                            })();
                            return ($t28860 && approaching);
                          }
                        })();
                        {
                          const $t28866 = (() => {
                            {
                              const $t28865 = (() => {
                                {
                                  const $t28864 = (() => {
                                    {
                                      const $t28862 = (dx * dx);
                                      {
                                        const $t28863 = (dy * dy);
                                        return ($t28862 + $t28863);
                                      }
                                    }
                                  })();
                                  return Math.sqrt($t28864);
                                }
                              })();
                              return ($t28865 <= grace);
                            }
                          })();
                          return ($t28861 && $t28866);
                        }
                      }
                    })();
                    if ($t28867 === true) {
                      return (() => {
                        {
                          const $t28868 = { _0: i, _1: s };
                          return { $: "Some", _0: $t28868 };
                        }
                      })();
                    } else {
                      return (() => {
                        {
                          const $t28869 = (i + 1);
                          return Perihelion$Core$find_capture(game, vx, vy, rest, $t28869);
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
    const $p28892 = Perihelion$Core$assisted_velocity(game, vx, vy, dt_s);
    {
      const vx2 = $p28892._0;
      {
        const vy2 = $p28892._1;
        {
          const g = (() => {
            {
              const $t28878 = (() => {
                {
                  const $t28876 = game.ball_x;
                  {
                    const $t28877 = (vx2 * dt_s);
                    return ($t28876 + $t28877);
                  }
                }
              })();
              {
                const $t28881 = (() => {
                  {
                    const $t28879 = game.ball_y;
                    {
                      const $t28880 = (vy2 * dt_s);
                      return ($t28879 + $t28880);
                    }
                  }
                })();
                {
                  const $t28882 = { $: "Flying", _0: vx2, _1: vy2 };
                  return ({ ...game, ball_x: $t28878, ball_y: $t28881, mode: $t28882 });
                }
              }
            }
          })();
          {
            const $t28884 = (() => {
              {
                const $t28883 = g.stars;
                return Perihelion$Core$find_capture(g, vx2, vy2, $t28883, 0);
              }
            })();
            switch ($t28884.$) {
              case "None": {
                return Perihelion$Core$check_death(g);
                break;
              }
              case "Some": {
                const $f28885 = $t28884._0;
                const $f28886 = $f28885._0;
                const $f28887 = $f28885._1;
                {
                  const t = $f28887;
                  {
                    const idx = $f28886;
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
        const $t28895 = (() => {
          {
            const $t28893 = game.ball_y;
            {
              const $t28894 = captured.y;
              return ($t28893 - $t28894);
            }
          }
        })();
        {
          const $t28898 = (() => {
            {
              const $t28896 = game.ball_x;
              {
                const $t28897 = captured.x;
                return ($t28896 - $t28897);
              }
            }
          })();
          return Math.atan2($t28895, $t28898);
        }
      }
    })();
    {
      const snapped = (() => {
        {
          const $t28900 = (() => {
            {
              const $t28899 = (() => {
                {
                  const $t28549_i5092 = Perihelion$Core$ring_count(captured);
                  return ($t28549_i5092 - 1);
                }
              })();
              return { $: "Orbiting", _0: idx, _1: $t28899, _2: angle };
            }
          })();
          {
            const $t28905 = (() => {
              {
                const $t28901 = captured.x;
                {
                  const $t28904 = (() => {
                    {
                      const $t28902 = Math.cos(angle);
                      {
                        const $t28903 = captured.capture_radius;
                        return ($t28902 * $t28903);
                      }
                    }
                  })();
                  return ($t28901 + $t28904);
                }
              }
            })();
            {
              const $t28910 = (() => {
                {
                  const $t28906 = captured.y;
                  {
                    const $t28909 = (() => {
                      {
                        const $t28907 = Math.sin(angle);
                        {
                          const $t28908 = captured.capture_radius;
                          return ($t28907 * $t28908);
                        }
                      }
                    })();
                    return ($t28906 + $t28909);
                  }
                }
              })();
              return ({ ...game, mode: $t28900, loop_angle: 0., ball_x: $t28905, ball_y: $t28910 });
            }
          }
        }
      })();
      {
        const $t28912 = (() => {
          {
            const $t28911 = game.current;
            return (idx > $t28911);
          }
        })();
        if ($t28912 === true) {
          return (() => {
            {
              const new_mult = (() => {
                {
                  const $t28915 = (() => {
                    {
                      const $t28913 = game.loop_angle;
                      return ($t28913 < 6.28318530718);
                    }
                  })();
                  if ($t28915 === true) {
                    return (() => {
                      {
                        const $t28919 = (() => {
                          {
                            const $t28917 = (() => {
                              {
                                const $t28916 = game.multiplier;
                                return ($t28916 + 1);
                              }
                            })();
                            return ($t28917 > 5);
                          }
                        })();
                        if ($t28919 === true) {
                          return 5;
                        } else {
                          return (() => {
                            {
                              const $t28920 = game.multiplier;
                              return ($t28920 + 1);
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
                    const $t28921 = game.stars_chained;
                    return ($t28921 + 1);
                  }
                })();
                {
                  const captured_game = (() => {
                    {
                      const $t28923 = (() => {
                        {
                          const $t28922 = game.score;
                          return ($t28922 + new_mult);
                        }
                      })();
                      {
                        const $t28925 = (() => {
                          {
                            const $t28924 = game.max_mult;
                            {
                              const $t28995_i5088 = ($t28924 > new_mult);
                              if ($t28995_i5088 === true) {
                                return $t28924;
                              } else {
                                return new_mult;
                              }
                            }
                          }
                        })();
                        {
                          const $t28929 = (() => {
                            {
                              const $t28926 = captured.x;
                              {
                                const $t28927 = captured.y;
                                {
                                  const $t28928 = { _0: $t28926, _1: $t28927 };
                                  return { $: "Some", _0: $t28928 };
                                }
                              }
                            }
                          })();
                          return ({ ...snapped, current: idx, score: $t28923, stars_chained: new_chained, multiplier: new_mult, max_mult: $t28925, capture_flash: $t28929 });
                        }
                      }
                    }
                  })();
                  {
                    const $t28930 = Perihelion$Upgrades$is_milestone(new_chained);
                    if ($t28930 === true) {
                      return (() => {
                        {
                          const $p28936 = (() => {
                            {
                              const $t28931 = captured_game.rng;
                              {
                                const $t28932 = captured_game.owned_weapons;
                                {
                                  const $t28933 = captured_game.special;
                                  return Perihelion$Upgrades$draw_choices($t28931, $t28932, $t28933);
                                }
                              }
                            }
                          })();
                          {
                            const rng2 = $p28936._0;
                            {
                              const choices = $p28936._1;
                              {
                                const $t28935 = (() => {
                                  {
                                    const $t28934 = { $: "Milestone" };
                                    return ({ ...captured_game, phase: $t28934, rng: rng2, milestone_choices: choices });
                                  }
                                })();
                                return Perihelion$Core$top_up($t28935);
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
        const $t28937 = { $: "Nil" };
        {
          const $t28938 = { $: "None" };
          return ({ ...game, fx_bursts: $t28937, capture_flash: $t28938 });
        }
      }
    })();
    switch (choice_idx.$) {
      case "None": {
        return g0;
        break;
      }
      case "Some": {
        const $f28946 = choice_idx._0;
        {
          const i = $f28946;
          {
            const $t28940 = (() => {
              {
                const $t28939 = g0.milestone_choices;
                return List$nth_opt$List_UpgradeKind$Int($t28939, i);
              }
            })();
            switch ($t28940.$) {
              case "None": {
                return g0;
                break;
              }
              case "Some": {
                const $f28945 = $t28940._0;
                {
                  const choice = $f28945;
                  {
                    const $t28944 = (() => {
                      {
                        const $t28941 = Perihelion$Core$apply_upgrade(g0, choice);
                        {
                          const $t28942 = { $: "Playing" };
                          {
                            const $t28943 = { $: "Nil" };
                            return ({ ...$t28941, phase: $t28942, milestone_choices: $t28943 });
                          }
                        }
                      }
                    })();
                    return Perihelion$Core$top_up($t28944);
                  }
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
      const $f28959 = u._0;
      {
        const k = $f28959;
        {
          const $t28948 = (() => {
            {
              const $t28947 = game.owned_weapons;
              {
                const $t690_i5104 = { $: "$Clo_$lam689$4780", _0: $lam689$apply$4780, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool($t28947, $t690_i5104);
              }
            }
          })();
          if ($t28948 === true) {
            return game;
          } else {
            return (() => {
              {
                const $t28949 = game.owned_weapons;
                {
                  const $t28950 = { $: "Nil" };
                  {
                    const $t28951 = { $: "Cons", _0: k, _1: $t28950 };
                    {
                      const $t28952 = (() => {
                        {
                          const go_i5100 = { $: "$Clo_go$4799", _0: go$apply$4799 };
                          {
                            const $t282_i5101 = (() => {
                              {
                                const go_i12071 = { $: "$Clo_go$5261", _0: go$apply$5261 };
                                {
                                  const $t274_i12072 = { $: "Nil" };
                                  return go$apply$5261(go_i12071, $t28949, $t274_i12072);
                                }
                              }
                            })();
                            return go$apply$4799(go_i5100, $t282_i5101, $t28951);
                          }
                        }
                      })();
                      return ({ ...game, owned_weapons: $t28952 });
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
        const $t28954 = (() => {
          {
            const $t28953 = game.fire_rate_stacks;
            return ($t28953 + 1);
          }
        })();
        return ({ ...game, fire_rate_stacks: $t28954 });
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
        const $t28956 = (() => {
          {
            const $t28955 = game.shield;
            return ($t28955 + 1);
          }
        })();
        return ({ ...game, shield: $t28956, shield_reinforced: true });
      }
      break;
    }
    case "SpecialItem": {
      const $f28960 = u._0;
      {
        const k = $f28960;
        {
          const $t28957 = (() => {
            return { $: "Some", _0: k };
          })();
          {
            const $t28958 = (() => {
              {
                let $rc_617;
                switch (k.$) {
                  case "StarThrust": {
                    $rc_617 = 3;
                    break;
                  }
                  case "StarJump": {
                    $rc_617 = 1;
                    break;
                  }
                  case "TrajectoryPreview": {
                    $rc_617 = 0;
                    break;
                  }
                  default: {
                    $rc_617 = (() => { throw new Error("non-exhaustive pattern match"); })();
                    break;
                  }
                }
                return $rc_617;
              }
            })();
            return ({ ...game, special: $t28957, special_charges: $t28958 });
          }
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
        const $t28962 = (() => {
          {
            const $t28961 = game.view_w;
            return ($t28961 / 2.);
          }
        })();
        {
          const $t28963 = ({ radius: 54., speed_mult: 1. });
          {
            const $t28964 = { $: "Nil" };
            {
              const $t28965 = { $: "Cons", _0: $t28963, _1: $t28964 };
              return ({ x: $t28962, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t28965 });
            }
          }
        }
      }
    })();
    {
      const top = (() => {
        {
          const $t28966 = game.stars;
          return Perihelion$Core$top_star($t28966, fallback);
        }
      })();
      {
        const $t28973 = (() => {
          {
            const $t28967 = top.y;
            {
              const $t28972 = (() => {
                {
                  const $t28968 = game.camera_y;
                  {
                    const $t28971 = (() => {
                      {
                        const $t28969 = game.view_h;
                        return ($t28969 * 1.5);
                      }
                    })();
                    return ($t28968 - $t28971);
                  }
                }
              })();
              return ($t28967 > $t28972);
            }
          }
        })();
        if ($t28973 === true) {
          return (() => {
            {
              const $p28984 = (() => {
                {
                  const $t28974 = game.rng;
                  {
                    const $t28975 = game.view_w;
                    return Perihelion$Level$next_star($t28974, top, $t28975);
                  }
                }
              })();
              {
                const fresh = $p28984._0;
                {
                  const rng2 = $p28984._1;
                  {
                    const g2 = (() => {
                      {
                        const $t28976 = game.stars;
                        {
                          const $t28977 = { $: "Nil" };
                          {
                            const $t28978 = { $: "Cons", _0: fresh, _1: $t28977 };
                            {
                              const $t28979 = (() => {
                                {
                                  const go_i5111 = { $: "$Clo_go$4787", _0: go$apply$4787 };
                                  {
                                    const $t282_i5112 = (() => {
                                      {
                                        const go_i12075 = { $: "$Clo_go$5259", _0: go$apply$5259 };
                                        {
                                          const $t274_i12076 = { $: "Nil" };
                                          return go$apply$5259(go_i12075, $t28976, $t274_i12076);
                                        }
                                      }
                                    })();
                                    return go$apply$4787(go_i5111, $t282_i5112, $t28978);
                                  }
                                }
                              })();
                              return ({ ...game, stars: $t28979, rng: rng2 });
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t28983 = (() => {
                        {
                          const $t28982 = (() => {
                            {
                              const $t28981 = (() => {
                                {
                                  const $t28980 = g2.stars;
                                  {
                                    const go_i5108 = { $: "$Clo_go$4747", _0: go$apply$4747 };
                                    return go$apply$4747(go_i5108, $t28980, 0);
                                  }
                                }
                              })();
                              return ($t28981 - 1);
                            }
                          })();
                          return Perihelion$Combat$maybe_spawn_ship(g2, $t28982);
                        }
                      })();
                      return Perihelion$Core$top_up($t28983);
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
      const $f28985 = stars._0;
      const $f28986 = stars._1;
      {
        const $jp_clo28992 = (() => {
          return { $: "$Clo_$jp28991$3773", _0: $jp28991$apply$3773, _1: $f28986, _2: fallback };
        })();
        switch ($f28986.$) {
          case "Nil": {
            {
              const s = $f28985;
              return s;
            }
            break;
          }
          default: {
            return $jp28991$apply$3773($jp_clo28992);
          }
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
        const $t28996 = game.score;
        {
          const $t28997 = game.stars_chained;
          {
            const $t28998 = game.max_mult;
            return ({ score: $t28996, stars: $t28997, max_mult: $t28998 });
          }
        }
      }
    })();
    {
      const $t28999 = { $: "Over" };
      {
        const $t29002 = (() => {
          {
            const $t29000 = game.best;
            {
              const $t29001 = game.score;
              {
                const $t28995_i5120 = ($t29000 > $t29001);
                if ($t28995_i5120 === true) {
                  return $t29000;
                } else {
                  return $t29001;
                }
              }
            }
          }
        })();
        {
          const $t29003 = game.runs;
          {
            const $t29004 = (() => {
              return { $: "Cons", _0: rec, _1: $t29003 };
            })();
            {
              const $t29005 = (() => {
                {
                  const go_i5116 = { $: "$Clo_go$4801", _0: go$apply$4801 };
                  {
                    const $t529_i5117 = { $: "Nil" };
                    return go$apply$4801(go_i5116, $t29004, 10, $t529_i5117);
                  }
                }
              })();
              return ({ ...game, phase: $t28999, best: $t29002, runs: $t29005 });
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
        const $t29006 = game.ball_y;
        {
          const $t29011 = (() => {
            {
              const $t29009 = (() => {
                {
                  const $t29007 = game.camera_y;
                  {
                    const $t29008 = game.view_h;
                    return ($t29007 + $t29008);
                  }
                }
              })();
              return ($t29009 + 40.);
            }
          })();
          return ($t29006 > $t29011);
        }
      }
    })();
    {
      const off_side = (() => {
        {
          const $t29015 = (() => {
            {
              const $t29012 = game.ball_x;
              {
                const $t29014 = (0. - 40.);
                return ($t29012 < $t29014);
              }
            }
          })();
          {
            const $t29020 = (() => {
              {
                const $t29016 = game.ball_x;
                {
                  const $t29019 = (() => {
                    {
                      const $t29017 = game.view_w;
                      return ($t29017 + 40.);
                    }
                  })();
                  return ($t29016 > $t29019);
                }
              }
            })();
            return ($t29015 || $t29020);
          }
        }
      })();
      {
        const fallback = (() => {
          {
            const $t29022 = (() => {
              {
                const $t29021 = game.view_w;
                return ($t29021 / 2.);
              }
            })();
            {
              const $t29023 = ({ radius: 54., speed_mult: 1. });
              {
                const $t29024 = { $: "Nil" };
                {
                  const $t29025 = { $: "Cons", _0: $t29023, _1: $t29024 };
                  return ({ x: $t29022, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29025 });
                }
              }
            }
          }
        })();
        {
          const topmost = (() => {
            {
              const $t29026 = game.stars;
              return Perihelion$Core$top_star($t29026, fallback);
            }
          })();
          {
            const overshot = (() => {
              {
                const $t29027 = game.ball_y;
                {
                  const $t29030 = (() => {
                    {
                      const $t29028 = topmost.y;
                      return ($t29028 - 150.);
                    }
                  })();
                  return ($t29027 < $t29030);
                }
              }
            })();
            {
              const fallen = (() => {
                {
                  const $t29031 = Perihelion$Core$star_at(game, 0);
                  switch ($t29031.$) {
                    case "None": {
                      return false;
                      break;
                    }
                    case "Some": {
                      const $f29036 = $t29031._0;
                      {
                        const c = $f29036;
                        {
                          const $t29032 = game.ball_y;
                          {
                            const $t29035 = (() => {
                              {
                                const $t29033 = c.y;
                                return ($t29033 + 200.);
                              }
                            })();
                            return ($t29032 > $t29035);
                          }
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
                const $t29039 = (() => {
                  {
                    const $t29038 = (() => {
                      {
                        const $t29037 = (below || off_side);
                        return ($t29037 || overshot);
                      }
                    })();
                    return ($t29038 || fallen);
                  }
                })();
                if ($t29039 === true) {
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
        const $t29040 = game.mode;
        switch ($t29040.$) {
          case "Flying": {
            const $f29047 = $t29040._0;
            const $f29048 = $t29040._1;
            (() => {
              return $f29047;
            })();
            return game.ball_x;
            break;
          }
          case "Orbiting": {
            const $f29053 = $t29040._0;
            const $f29054 = $t29040._1;
            const $f29055 = $t29040._2;
            {
              const $t29042 = (() => {
                {
                  const $t29041 = game.current;
                  return Perihelion$Core$star_at(game, $t29041);
                }
              })();
              switch ($t29042.$) {
                case "None": {
                  {
                    const $t29043 = game.camera_x;
                    {
                      const $t29045 = (() => {
                        {
                          const $t29044 = game.view_w;
                          return ($t29044 / 2.);
                        }
                      })();
                      return ($t29043 + $t29045);
                    }
                  }
                  break;
                }
                case "Some": {
                  const $f29046 = $t29042._0;
                  {
                    const s = $f29046;
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
          const $t29064 = game.mode;
          switch ($t29064.$) {
            case "Flying": {
              const $f29076 = $t29064._0;
              const $f29077 = $t29064._1;
              {
                const $t29065 = game.ball_y;
                {
                  const $t29068 = (() => {
                    {
                      const $t29067 = game.view_h;
                      return (0.6 * $t29067);
                    }
                  })();
                  return ($t29065 - $t29068);
                }
              }
              break;
            }
            case "Orbiting": {
              const $f29082 = $t29064._0;
              const $f29083 = $t29064._1;
              const $f29084 = $t29064._2;
              {
                const $t29070 = (() => {
                  {
                    const $t29069 = game.current;
                    return Perihelion$Core$star_at(game, $t29069);
                  }
                })();
                switch ($t29070.$) {
                  case "None": {
                    return game.camera_y;
                    break;
                  }
                  case "Some": {
                    const $f29075 = $t29070._0;
                    {
                      const s = $f29075;
                      {
                        const $t29071 = s.y;
                        {
                          const $t29074 = (() => {
                            {
                              const $t29073 = game.view_h;
                              return (0.6 * $t29073);
                            }
                          })();
                          return ($t29071 - $t29074);
                        }
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
            const $t29093 = game.view_w;
            return ($t29093 * 0.25);
          }
        })();
        {
          const right_edge = (() => {
            {
              const $t29095 = game.view_w;
              {
                const $t29097 = (1. - 0.25);
                return ($t29095 * $t29097);
              }
            }
          })();
          {
            const screen_x = (() => {
              {
                const $t29098 = game.camera_x;
                return (focus_x - $t29098);
              }
            })();
            {
              const target_x = (() => {
                {
                  const $t29099 = (screen_x < left_edge);
                  if ($t29099 === true) {
                    return (focus_x - left_edge);
                  } else {
                    return (() => {
                      {
                        const $t29100 = (screen_x > right_edge);
                        if ($t29100 === true) {
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
                const $t29107 = (() => {
                  {
                    const $t29101 = game.camera_y;
                    {
                      const $t29106 = (() => {
                        {
                          const $t29105 = (() => {
                            {
                              const $t29103 = (() => {
                                {
                                  const $t29102 = game.camera_y;
                                  return (target_y - $t29102);
                                }
                              })();
                              return ($t29103 * 3.);
                            }
                          })();
                          return ($t29105 * dt_s);
                        }
                      })();
                      return ($t29101 + $t29106);
                    }
                  }
                })();
                {
                  const $t29114 = (() => {
                    {
                      const $t29108 = game.camera_x;
                      {
                        const $t29113 = (() => {
                          {
                            const $t29112 = (() => {
                              {
                                const $t29110 = (() => {
                                  {
                                    const $t29109 = game.camera_x;
                                    return (target_x - $t29109);
                                  }
                                })();
                                return ($t29110 * 3.);
                              }
                            })();
                            return ($t29112 * dt_s);
                          }
                        })();
                        return ($t29108 + $t29113);
                      }
                    }
                  })();
                  return ({ ...game, camera_y: $t29107, camera_x: $t29114 });
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
    const $p29168 = (() => {
      {
        const $t29115 = Random$seed(seed);
        return Perihelion$Level$initial_stars($t29115, view_w);
      }
    })();
    {
      const stars = $p29168._0;
      {
        const rng2 = $p29168._1;
        {
          const start_angle = (3.14159265359 / 2.);
          switch (stars.$) {
            case "Nil": {
              {
                const $t29117 = { $: "Ready" };
                {
                  const $t29118 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                  {
                    const $t29119 = { $: "Nil" };
                    {
                      const $t29120 = { $: "Nil" };
                      {
                        const $t29121 = { $: "Nil" };
                        {
                          const $t29122 = { $: "Nil" };
                          {
                            const $t29123 = { $: "Nil" };
                            {
                              const $t29124 = { $: "Nil" };
                              {
                                const $t29125 = { $: "Base" };
                                {
                                  const $t29126 = { $: "Nil" };
                                  {
                                    const $t29127 = { $: "Cons", _0: $t29125, _1: $t29126 };
                                    {
                                      const $t29128 = { $: "None" };
                                      {
                                        const $t29129 = { $: "Nil" };
                                        {
                                          const $t29131 = { $: "Nil" };
                                          {
                                            const $t29132 = { $: "None" };
                                            return ({ seed: seed, phase: $t29117, ball_x: 0., ball_y: 0., mode: $t29118, stars: $t29119, current: 0, score: 0, best: best, camera_y: 0., camera_x: 0., rng: rng2, asteroids: $t29120, ships: $t29121, player_shots: $t29122, enemy_shots: $t29123, pickups: $t29124, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t29127, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t29128, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t29129, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t29131, capture_flash: $t29132 });
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
              const $f29162 = stars._0;
              const $f29163 = stars._1;
              {
                const s0 = (() => {
                  return $f29162;
                })();
                {
                  const $t29133 = { $: "Ready" };
                  {
                    const $t29138 = (() => {
                      {
                        const $t29134 = s0.x;
                        {
                          const $t29137 = (() => {
                            {
                              const $t29135 = Math.cos(start_angle);
                              {
                                const $t29136 = s0.capture_radius;
                                return ($t29135 * $t29136);
                              }
                            }
                          })();
                          return ($t29134 + $t29137);
                        }
                      }
                    })();
                    {
                      const $t29143 = (() => {
                        {
                          const $t29139 = s0.y;
                          {
                            const $t29142 = (() => {
                              {
                                const $t29140 = Math.sin(start_angle);
                                {
                                  const $t29141 = s0.capture_radius;
                                  return ($t29140 * $t29141);
                                }
                              }
                            })();
                            return ($t29139 + $t29142);
                          }
                        }
                      })();
                      {
                        const $t29144 = { $: "Orbiting", _0: 0, _1: 0, _2: start_angle };
                        {
                          const $t29148 = (() => {
                            {
                              const $t29145 = s0.y;
                              {
                                const $t29147 = (0.6 * view_h);
                                return ($t29145 - $t29147);
                              }
                            }
                          })();
                          {
                            const $t29149 = { $: "Nil" };
                            {
                              const $t29150 = { $: "Nil" };
                              {
                                const $t29151 = { $: "Nil" };
                                {
                                  const $t29152 = { $: "Nil" };
                                  {
                                    const $t29153 = { $: "Nil" };
                                    {
                                      const $t29154 = { $: "Base" };
                                      {
                                        const $t29155 = { $: "Nil" };
                                        {
                                          const $t29156 = { $: "Cons", _0: $t29154, _1: $t29155 };
                                          {
                                            const $t29157 = { $: "None" };
                                            {
                                              const $t29158 = { $: "Nil" };
                                              {
                                                const $t29160 = { $: "Nil" };
                                                {
                                                  const $t29161 = { $: "None" };
                                                  return ({ seed: seed, phase: $t29133, ball_x: $t29138, ball_y: $t29143, mode: $t29144, stars: stars, current: 0, score: 0, best: best, camera_y: $t29148, camera_x: 0., rng: rng2, asteroids: $t29149, ships: $t29150, player_shots: $t29151, enemy_shots: $t29152, pickups: $t29153, shield: 0, multiplier: 1, max_mult: 1, owned_weapons: $t29156, active_weapon_idx: 0, fire_rate_stacks: 0, bullet_ward: false, deflector_plating: false, shield_reinforced: false, special: $t29157, special_charges: 0, starkiller_target_offset: 0, starkiller_cooldown: 0., milestone_choices: $t29158, stars_chained: 0, loop_angle: 0., fire_cooldown: 0., spawn_timer: 4., runs: runs, view_w: view_w, view_h: view_h, fx_bursts: $t29160, capture_flash: $t29161 });
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
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
        const $t29174 = (() => {
          {
            const $p29173_i5147 = (() => {
              {
                const $t29172_i5146 = game.rng;
                {
                  const $p15858_i12078 = Random$next_raw($t29172_i5146);
                  {
                    const hi_i12079 = $p15858_i12078._0;
                    {
                      const rng2_i12080 = $p15858_i12078._1;
                      {
                        const $p15857_i12081 = Random$next_raw(rng2_i12080);
                        {
                          const lo_i12082 = $p15857_i12081._0;
                          {
                            const rng3_i12083 = $p15857_i12081._1;
                            {
                              const $t15856_i12087 = (() => {
                                {
                                  const $t15855_i12086 = (() => {
                                    {
                                      const $t15853_i12084 = march_int_and(hi_i12079, 1048575);
                                      return ($t15853_i12084 * 4294967296);
                                    }
                                  })();
                                  return ($t15855_i12086 + lo_i12082);
                                }
                              })();
                              return { _0: $t15856_i12087, _1: rng3_i12083 };
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
              const s_i5148 = $p29173_i5147._0;
              return s_i5148;
            }
          }
        })();
        {
          const $t29175 = game.best;
          {
            const $t29176 = game.runs;
            {
              const $t29177 = game.view_w;
              {
                const $t29178 = game.view_h;
                return Perihelion$Core$fresh_run($t29174, $t29175, $t29176, $t29177, $t29178);
              }
            }
          }
        }
      }
    })();
    {
      const $t29179 = { $: "Playing" };
      return ({ ...g, phase: $t29179 });
    }
  }
}
const Perihelion$Core$restart$clo = { _0: ($_, game) => Perihelion$Core$restart(game) };

function Perihelion$Core$reset(game) {
  {
    const $t29180 = (() => {
      {
        const $p29173_i5151 = (() => {
          {
            const $t29172_i5150 = game.rng;
            {
              const $p15858_i12089 = Random$next_raw($t29172_i5150);
              {
                const hi_i12090 = $p15858_i12089._0;
                {
                  const rng2_i12091 = $p15858_i12089._1;
                  {
                    const $p15857_i12092 = Random$next_raw(rng2_i12091);
                    {
                      const lo_i12093 = $p15857_i12092._0;
                      {
                        const rng3_i12094 = $p15857_i12092._1;
                        {
                          const $t15856_i12098 = (() => {
                            {
                              const $t15855_i12097 = (() => {
                                {
                                  const $t15853_i12095 = march_int_and(hi_i12090, 1048575);
                                  return ($t15853_i12095 * 4294967296);
                                }
                              })();
                              return ($t15855_i12097 + lo_i12093);
                            }
                          })();
                          return { _0: $t15856_i12098, _1: rng3_i12094 };
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
          const s_i5152 = $p29173_i5151._0;
          return s_i5152;
        }
      }
    })();
    {
      const $t29181 = game.best;
      {
        const $t29182 = game.runs;
        {
          const $t29183 = game.view_w;
          {
            const $t29184 = game.view_h;
            return Perihelion$Core$fresh_run($t29180, $t29181, $t29182, $t29183, $t29184);
          }
        }
      }
    }
  }
}
const Perihelion$Core$reset$clo = { _0: ($_, game) => Perihelion$Core$reset(game) };

function Perihelion$Core$encode_run(r) {
  {
    const $t29189 = (() => {
      {
        const $t29186 = (() => {
          {
            const $t29185 = r.score;
            return String($t29185);
          }
        })();
        {
          const $t29188 = (() => {
            {
              const $t29187 = r.stars;
              return String($t29187);
            }
          })();
          {
            const $rc_619 = march_string_concat3($t29186, ":", $t29188);
            return $rc_619;
          }
        }
      }
    })();
    {
      const $t29191 = (() => {
        {
          const $t29190 = r.max_mult;
          return String($t29190);
        }
      })();
      {
        const $rc_618 = march_string_concat3($t29189, ":", $t29191);
        return $rc_618;
      }
    }
  }
}
const Perihelion$Core$encode_run$clo = { _0: ($_, r) => Perihelion$Core$encode_run(r) };

function Perihelion$Core$encode_save(best, runs) {
  {
    const $t29192 = String(best);
    {
      const $t29196 = (() => {
        {
          const $t29194 = { $: "$Clo_$lam29193$3785", _0: $lam29193$apply$3785 };
          {
            const $t29195 = (() => {
              {
                const f_i5156 = $t29194;
                {
                  const go_i5157 = { $: "$Clo_go$4803", _0: go$apply$4803, _1: f_i5156 };
                  {
                    const $t291_i5158 = { $: "Nil" };
                    return go$apply$4803(go_i5157, runs, $t291_i5158);
                  }
                }
              }
            })();
            return march_string_join($t29195, ";");
          }
        }
      })();
      {
        const $rc_620 = march_string_concat3($t29192, "|", $t29196);
        return $rc_620;
      }
    }
  }
}
const Perihelion$Core$encode_save$clo = { _0: ($_, best, runs) => Perihelion$Core$encode_save(best, runs) };

function Perihelion$Core$decode_run(s) {
  {
    const $t29197 = march_string_split(s, ":");
    switch ($t29197.$) {
      case "Cons": {
        const $f29205 = $t29197._0;
        const $f29206 = $t29197._1;
        {
          const $jp_clo29208 = { $: "$Clo_$jp29207$3786", _0: $jp29207$apply$3786 };
          {
            const $jp_clo29212 = { $: "$Clo_$jp29211$3787", _0: $jp29211$apply$3787$clo, _1: $jp_clo29208 };
            switch ($f29206.$) {
              case "Cons": {
                const $f29213 = $f29206._0;
                const $f29214 = $f29206._1;
                {
                  const $jp_clo29216 = { $: "$Clo_$jp29215$3789", _0: $jp29215$apply$3789, _1: $jp_clo29212 };
                  {
                    const $jp_clo29220 = { $: "$Clo_$jp29219$3790", _0: $jp29219$apply$3790, _1: $jp_clo29216 };
                    switch ($f29214.$) {
                      case "Cons": {
                        const $f29221 = $f29214._0;
                        const $f29222 = $f29214._1;
                        {
                          const $jp_clo29224 = { $: "$Clo_$jp29223$3792", _0: $jp29223$apply$3792, _1: $jp_clo29220 };
                          {
                            const $jp_clo29228 = { $: "$Clo_$jp29227$3793", _0: $jp29227$apply$3793, _1: $jp_clo29224 };
                            switch ($f29222.$) {
                              case "Nil": {
                                {
                                  const c = $f29221;
                                  {
                                    const b = $f29213;
                                    {
                                      const a = $f29205;
                                      {
                                        const $t29198 = (() => {
                                          {
                                            const $rc_623 = march_string_to_int(a);
                                            return $rc_623;
                                          }
                                        })();
                                        switch ($t29198.$) {
                                          case "None": {
                                            return { $: "None" };
                                            break;
                                          }
                                          case "Some": {
                                            const $f29204 = $t29198._0;
                                            {
                                              const score = $f29204;
                                              {
                                                const $t29199 = (() => {
                                                  {
                                                    const $rc_622 = march_string_to_int(b);
                                                    return $rc_622;
                                                  }
                                                })();
                                                switch ($t29199.$) {
                                                  case "None": {
                                                    return { $: "None" };
                                                    break;
                                                  }
                                                  case "Some": {
                                                    const $f29203 = $t29199._0;
                                                    {
                                                      const stars = $f29203;
                                                      {
                                                        const $t29200 = (() => {
                                                          {
                                                            const $rc_621 = march_string_to_int(c);
                                                            return $rc_621;
                                                          }
                                                        })();
                                                        switch ($t29200.$) {
                                                          case "None": {
                                                            return { $: "None" };
                                                            break;
                                                          }
                                                          case "Some": {
                                                            const $f29202 = $t29200._0;
                                                            {
                                                              const mm = $f29202;
                                                              {
                                                                const $t29201 = ({ score: score, stars: stars, max_mult: mm });
                                                                return { $: "Some", _0: $t29201 };
                                                              }
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
                                return $jp29227$apply$3793($jp_clo29228);
                              }
                            }
                          }
                        }
                        break;
                      }
                      default: {
                        return $jp29219$apply$3790($jp_clo29220);
                      }
                    }
                  }
                }
                break;
              }
              default: {
                return $jp29211$apply$3787($jp_clo29212);
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
        const $t29231 = (() => {
          {
            const go_i5166 = { $: "$Clo_go$4805", _0: go$apply$4805 };
            {
              const $t274_i5167 = { $: "Nil" };
              return go$apply$4805(go_i5166, acc, $t274_i5167);
            }
          }
        })();
        return { $: "Some", _0: $t29231 };
      }
      break;
    }
    case "Cons": {
      const $f29235 = parts._0;
      const $f29236 = parts._1;
      {
        const rest = $f29236;
        {
          const p = $f29235;
          {
            const $t29232 = (() => {
              {
                const $rc_624 = Perihelion$Core$decode_run(p);
                return $rc_624;
              }
            })();
            switch ($t29232.$) {
              case "None": {
                return { $: "None" };
                break;
              }
              case "Some": {
                const $f29234 = $t29232._0;
                {
                  const r = $f29234;
                  {
                    const $t29233 = { $: "Cons", _0: r, _1: acc };
                    return Perihelion$Core$decode_runs(rest, $t29233);
                  }
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
        const $t29241 = { $: "Nil" };
        return { _0: 0, _1: $t29241 };
      }
    })();
    {
      const $t29242 = march_string_split(s, "|");
      switch ($t29242.$) {
        case "Cons": {
          const $f29252 = $t29242._0;
          const $f29253 = $t29242._1;
          switch ($f29253.$) {
            case "Cons": {
              const $f29254 = $f29253._0;
              const $f29255 = $f29253._1;
              switch ($f29255.$) {
                case "Nil": {
                  {
                    const runs_s = $f29254;
                    {
                      const best_s = $f29252;
                      {
                        const $t29243 = (() => {
                          {
                            const $rc_626 = march_string_to_int(best_s);
                            return $rc_626;
                          }
                        })();
                        switch ($t29243.$) {
                          case "None": {
                            return zero;
                            break;
                          }
                          case "Some": {
                            const $f29251 = $t29243._0;
                            {
                              const best = $f29251;
                              if (runs_s === "") {
                                return (() => {
                                  {
                                    const $t29244 = { $: "Nil" };
                                    return { _0: best, _1: $t29244 };
                                  }
                                })();
                              } else {
                                return (() => {
                                  {
                                    const $t29247 = (() => {
                                      {
                                        const $t29245 = (() => {
                                          {
                                            const $rc_625 = march_string_split(runs_s, ";");
                                            return $rc_625;
                                          }
                                        })();
                                        {
                                          const $t29246 = { $: "Nil" };
                                          return Perihelion$Core$decode_runs($t29245, $t29246);
                                        }
                                      }
                                    })();
                                    switch ($t29247.$) {
                                      case "None": {
                                        return zero;
                                        break;
                                      }
                                      case "Some": {
                                        const $f29248 = $t29247._0;
                                        {
                                          const rs = $f29248;
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
        const $t29261 = ({ radius: outer_r, speed_mult: outer_sp });
        {
          const $t29262 = { $: "Nil" };
          return { $: "Cons", _0: $t29261, _1: $t29262 };
        }
      }
    })();
  } else if (n === 2) {
    return (() => {
      {
        const $t29265 = (() => {
          {
            const $t29263 = (outer_r * 0.6);
            {
              const $t29264 = (outer_sp * 1.5);
              return ({ radius: $t29263, speed_mult: $t29264 });
            }
          }
        })();
        {
          const $t29266 = ({ radius: outer_r, speed_mult: outer_sp });
          {
            const $t29267 = { $: "Nil" };
            {
              const $t29268 = { $: "Cons", _0: $t29266, _1: $t29267 };
              return { $: "Cons", _0: $t29265, _1: $t29268 };
            }
          }
        }
      }
    })();
  } else {
    return (() => {
      {
        const $t29271 = (() => {
          {
            const $t29269 = (outer_r * 0.5);
            {
              const $t29270 = (outer_sp * 1.8);
              return ({ radius: $t29269, speed_mult: $t29270 });
            }
          }
        })();
        {
          const $t29274 = (() => {
            {
              const $t29272 = (outer_r * 0.75);
              {
                const $t29273 = (outer_sp * 1.35);
                return ({ radius: $t29272, speed_mult: $t29273 });
              }
            }
          })();
          {
            const $t29275 = ({ radius: outer_r, speed_mult: outer_sp });
            {
              const $t29276 = { $: "Nil" };
              {
                const $t29277 = { $: "Cons", _0: $t29275, _1: $t29276 };
                {
                  const $t29278 = { $: "Cons", _0: $t29274, _1: $t29277 };
                  return { $: "Cons", _0: $t29271, _1: $t29278 };
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
    const $p29308 = (() => {
      {
        const $p29256_i5245 = (() => {
          {
            const $p15861_i12217 = (() => {
              {
                const $p15858_i1974_i12207 = Random$next_raw(rng);
                {
                  const hi_i1975_i12208 = $p15858_i1974_i12207._0;
                  {
                    const rng2_i1976_i12209 = $p15858_i1974_i12207._1;
                    {
                      const $p15857_i1977_i12210 = Random$next_raw(rng2_i1976_i12209);
                      {
                        const lo_i1978_i12211 = $p15857_i1977_i12210._0;
                        {
                          const rng3_i1979_i12212 = $p15857_i1977_i12210._1;
                          {
                            const $t15856_i1983_i12216 = (() => {
                              {
                                const $t15855_i1982_i12215 = (() => {
                                  {
                                    const $t15853_i1980_i12213 = march_int_and(hi_i1975_i12208, 1048575);
                                    return ($t15853_i1980_i12213 * 4294967296);
                                  }
                                })();
                                return ($t15855_i1982_i12215 + lo_i1978_i12211);
                              }
                            })();
                            return { _0: $t15856_i1983_i12216, _1: rng3_i1979_i12212 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i12218 = $p15861_i12217._0;
              {
                const rng2_i12219 = $p15861_i12217._1;
                {
                  const $t15860_i12221 = (() => {
                    {
                      const $t15859_i12220 = bits_i12218;
                      return ($t15859_i12220 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15860_i12221, _1: rng2_i12219 };
                }
              }
            }
          }
        })();
        {
          const t_i5246 = $p29256_i5245._0;
          {
            const rng2_i5247 = $p29256_i5245._1;
            {
              const out_i5248 = { _0: rng2_i5247, _1: t_i5246 };
              return out_i5248;
            }
          }
        }
      }
    })();
    {
      const r1 = $p29308._0;
      {
        const ty = $p29308._1;
        {
          const $p29307 = (() => {
            {
              const $p29256_i5240 = (() => {
                {
                  const $p15861_i12201 = (() => {
                    {
                      const $p15858_i1974_i12191 = Random$next_raw(r1);
                      {
                        const hi_i1975_i12192 = $p15858_i1974_i12191._0;
                        {
                          const rng2_i1976_i12193 = $p15858_i1974_i12191._1;
                          {
                            const $p15857_i1977_i12194 = Random$next_raw(rng2_i1976_i12193);
                            {
                              const lo_i1978_i12195 = $p15857_i1977_i12194._0;
                              {
                                const rng3_i1979_i12196 = $p15857_i1977_i12194._1;
                                {
                                  const $t15856_i1983_i12200 = (() => {
                                    {
                                      const $t15855_i1982_i12199 = (() => {
                                        {
                                          const $t15853_i1980_i12197 = march_int_and(hi_i1975_i12192, 1048575);
                                          return ($t15853_i1980_i12197 * 4294967296);
                                        }
                                      })();
                                      return ($t15855_i1982_i12199 + lo_i1978_i12195);
                                    }
                                  })();
                                  return { _0: $t15856_i1983_i12200, _1: rng3_i1979_i12196 };
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  })();
                  {
                    const bits_i12202 = $p15861_i12201._0;
                    {
                      const rng2_i12203 = $p15861_i12201._1;
                      {
                        const $t15860_i12205 = (() => {
                          {
                            const $t15859_i12204 = bits_i12202;
                            return ($t15859_i12204 / 4.50359962737e+15);
                          }
                        })();
                        return { _0: $t15860_i12205, _1: rng2_i12203 };
                      }
                    }
                  }
                }
              })();
              {
                const t_i5241 = $p29256_i5240._0;
                {
                  const rng2_i5242 = $p29256_i5240._1;
                  {
                    const out_i5243 = { _0: rng2_i5242, _1: t_i5241 };
                    return out_i5243;
                  }
                }
              }
            }
          })();
          {
            const r2 = $p29307._0;
            {
              const tx = $p29307._1;
              {
                const $p29306 = (() => {
                  {
                    const $p29256_i5235 = (() => {
                      {
                        const $p15861_i12185 = (() => {
                          {
                            const $p15858_i1974_i12175 = Random$next_raw(r2);
                            {
                              const hi_i1975_i12176 = $p15858_i1974_i12175._0;
                              {
                                const rng2_i1976_i12177 = $p15858_i1974_i12175._1;
                                {
                                  const $p15857_i1977_i12178 = Random$next_raw(rng2_i1976_i12177);
                                  {
                                    const lo_i1978_i12179 = $p15857_i1977_i12178._0;
                                    {
                                      const rng3_i1979_i12180 = $p15857_i1977_i12178._1;
                                      {
                                        const $t15856_i1983_i12184 = (() => {
                                          {
                                            const $t15855_i1982_i12183 = (() => {
                                              {
                                                const $t15853_i1980_i12181 = march_int_and(hi_i1975_i12176, 1048575);
                                                return ($t15853_i1980_i12181 * 4294967296);
                                              }
                                            })();
                                            return ($t15855_i1982_i12183 + lo_i1978_i12179);
                                          }
                                        })();
                                        return { _0: $t15856_i1983_i12184, _1: rng3_i1979_i12180 };
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        })();
                        {
                          const bits_i12186 = $p15861_i12185._0;
                          {
                            const rng2_i12187 = $p15861_i12185._1;
                            {
                              const $t15860_i12189 = (() => {
                                {
                                  const $t15859_i12188 = bits_i12186;
                                  return ($t15859_i12188 / 4.50359962737e+15);
                                }
                              })();
                              return { _0: $t15860_i12189, _1: rng2_i12187 };
                            }
                          }
                        }
                      }
                    })();
                    {
                      const t_i5236 = $p29256_i5235._0;
                      {
                        const rng2_i5237 = $p29256_i5235._1;
                        {
                          const out_i5238 = { _0: rng2_i5237, _1: t_i5236 };
                          return out_i5238;
                        }
                      }
                    }
                  }
                })();
                {
                  const r3 = $p29306._0;
                  {
                    const tr = $p29306._1;
                    {
                      const $p29305 = (() => {
                        {
                          const $p29256_i5230 = (() => {
                            {
                              const $p15861_i12169 = (() => {
                                {
                                  const $p15858_i1974_i12159 = Random$next_raw(r3);
                                  {
                                    const hi_i1975_i12160 = $p15858_i1974_i12159._0;
                                    {
                                      const rng2_i1976_i12161 = $p15858_i1974_i12159._1;
                                      {
                                        const $p15857_i1977_i12162 = Random$next_raw(rng2_i1976_i12161);
                                        {
                                          const lo_i1978_i12163 = $p15857_i1977_i12162._0;
                                          {
                                            const rng3_i1979_i12164 = $p15857_i1977_i12162._1;
                                            {
                                              const $t15856_i1983_i12168 = (() => {
                                                {
                                                  const $t15855_i1982_i12167 = (() => {
                                                    {
                                                      const $t15853_i1980_i12165 = march_int_and(hi_i1975_i12160, 1048575);
                                                      return ($t15853_i1980_i12165 * 4294967296);
                                                    }
                                                  })();
                                                  return ($t15855_i1982_i12167 + lo_i1978_i12163);
                                                }
                                              })();
                                              return { _0: $t15856_i1983_i12168, _1: rng3_i1979_i12164 };
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              })();
                              {
                                const bits_i12170 = $p15861_i12169._0;
                                {
                                  const rng2_i12171 = $p15861_i12169._1;
                                  {
                                    const $t15860_i12173 = (() => {
                                      {
                                        const $t15859_i12172 = bits_i12170;
                                        return ($t15859_i12172 / 4.50359962737e+15);
                                      }
                                    })();
                                    return { _0: $t15860_i12173, _1: rng2_i12171 };
                                  }
                                }
                              }
                            }
                          })();
                          {
                            const t_i5231 = $p29256_i5230._0;
                            {
                              const rng2_i5232 = $p29256_i5230._1;
                              {
                                const out_i5233 = { _0: rng2_i5232, _1: t_i5231 };
                                return out_i5233;
                              }
                            }
                          }
                        }
                      })();
                      {
                        const r4 = $p29305._0;
                        {
                          const tcm = $p29305._1;
                          {
                            const $p29304 = (() => {
                              {
                                const $p29256_i5225 = (() => {
                                  {
                                    const $p15861_i12153 = (() => {
                                      {
                                        const $p15858_i1974_i12143 = Random$next_raw(r4);
                                        {
                                          const hi_i1975_i12144 = $p15858_i1974_i12143._0;
                                          {
                                            const rng2_i1976_i12145 = $p15858_i1974_i12143._1;
                                            {
                                              const $p15857_i1977_i12146 = Random$next_raw(rng2_i1976_i12145);
                                              {
                                                const lo_i1978_i12147 = $p15857_i1977_i12146._0;
                                                {
                                                  const rng3_i1979_i12148 = $p15857_i1977_i12146._1;
                                                  {
                                                    const $t15856_i1983_i12152 = (() => {
                                                      {
                                                        const $t15855_i1982_i12151 = (() => {
                                                          {
                                                            const $t15853_i1980_i12149 = march_int_and(hi_i1975_i12144, 1048575);
                                                            return ($t15853_i1980_i12149 * 4294967296);
                                                          }
                                                        })();
                                                        return ($t15855_i1982_i12151 + lo_i1978_i12147);
                                                      }
                                                    })();
                                                    return { _0: $t15856_i1983_i12152, _1: rng3_i1979_i12148 };
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    })();
                                    {
                                      const bits_i12154 = $p15861_i12153._0;
                                      {
                                        const rng2_i12155 = $p15861_i12153._1;
                                        {
                                          const $t15860_i12157 = (() => {
                                            {
                                              const $t15859_i12156 = bits_i12154;
                                              return ($t15859_i12156 / 4.50359962737e+15);
                                            }
                                          })();
                                          return { _0: $t15860_i12157, _1: rng2_i12155 };
                                        }
                                      }
                                    }
                                  }
                                })();
                                {
                                  const t_i5226 = $p29256_i5225._0;
                                  {
                                    const rng2_i5227 = $p29256_i5225._1;
                                    {
                                      const out_i5228 = { _0: rng2_i5227, _1: t_i5226 };
                                      return out_i5228;
                                    }
                                  }
                                }
                              }
                            })();
                            {
                              const r5 = $p29304._0;
                              {
                                const tsm = $p29304._1;
                                {
                                  const $p29303 = (() => {
                                    {
                                      const $p29256_i5220 = (() => {
                                        {
                                          const $p15861_i12137 = (() => {
                                            {
                                              const $p15858_i1974_i12127 = Random$next_raw(r5);
                                              {
                                                const hi_i1975_i12128 = $p15858_i1974_i12127._0;
                                                {
                                                  const rng2_i1976_i12129 = $p15858_i1974_i12127._1;
                                                  {
                                                    const $p15857_i1977_i12130 = Random$next_raw(rng2_i1976_i12129);
                                                    {
                                                      const lo_i1978_i12131 = $p15857_i1977_i12130._0;
                                                      {
                                                        const rng3_i1979_i12132 = $p15857_i1977_i12130._1;
                                                        {
                                                          const $t15856_i1983_i12136 = (() => {
                                                            {
                                                              const $t15855_i1982_i12135 = (() => {
                                                                {
                                                                  const $t15853_i1980_i12133 = march_int_and(hi_i1975_i12128, 1048575);
                                                                  return ($t15853_i1980_i12133 * 4294967296);
                                                                }
                                                              })();
                                                              return ($t15855_i1982_i12135 + lo_i1978_i12131);
                                                            }
                                                          })();
                                                          return { _0: $t15856_i1983_i12136, _1: rng3_i1979_i12132 };
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          })();
                                          {
                                            const bits_i12138 = $p15861_i12137._0;
                                            {
                                              const rng2_i12139 = $p15861_i12137._1;
                                              {
                                                const $t15860_i12141 = (() => {
                                                  {
                                                    const $t15859_i12140 = bits_i12138;
                                                    return ($t15859_i12140 / 4.50359962737e+15);
                                                  }
                                                })();
                                                return { _0: $t15860_i12141, _1: rng2_i12139 };
                                              }
                                            }
                                          }
                                        }
                                      })();
                                      {
                                        const t_i5221 = $p29256_i5220._0;
                                        {
                                          const rng2_i5222 = $p29256_i5220._1;
                                          {
                                            const out_i5223 = { _0: rng2_i5222, _1: t_i5221 };
                                            return out_i5223;
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  {
                                    const r6 = $p29303._0;
                                    {
                                      const trings = $p29303._1;
                                      {
                                        const gap = (() => {
                                          {
                                            const $t29258_i5218 = (() => {
                                              {
                                                const $t29257_i5217 = (260. - 160.);
                                                return (ty * $t29257_i5217);
                                              }
                                            })();
                                            return (160. + $t29258_i5218);
                                          }
                                        })();
                                        {
                                          const dx = (() => {
                                            {
                                              const $t29286 = (0. - 220.);
                                              {
                                                const $t29258_i5213 = (() => {
                                                  {
                                                    const $t29257_i5212 = (220. - $t29286);
                                                    return (tx * $t29257_i5212);
                                                  }
                                                })();
                                                return ($t29286 + $t29258_i5213);
                                              }
                                            }
                                          })();
                                          {
                                            const x = (() => {
                                              {
                                                const $t29289 = (() => {
                                                  {
                                                    const $t29288 = prev.x;
                                                    return ($t29288 + dx);
                                                  }
                                                })();
                                                {
                                                  const $t29292 = (view_w - 60.);
                                                  {
                                                    const $t1601_i5207 = ($t29289 < 60.);
                                                    if ($t1601_i5207 === true) {
                                                      return 60.;
                                                    } else {
                                                      return (() => {
                                                        {
                                                          const $t1602_i5208 = ($t29289 > $t29292);
                                                          if ($t1602_i5208 === true) {
                                                            return $t29292;
                                                          } else {
                                                            return $t29289;
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
                                                  const $t29295 = (tr * tr);
                                                  {
                                                    const $t29258_i5203 = (() => {
                                                      {
                                                        const $t29257_i5202 = (20. - 8.);
                                                        return ($t29295 * $t29257_i5202);
                                                      }
                                                    })();
                                                    return (8. + $t29258_i5203);
                                                  }
                                                }
                                              })();
                                              {
                                                const cm = (() => {
                                                  {
                                                    const $t29258_i5198 = (() => {
                                                      {
                                                        const $t29257_i5197 = (5.2 - 2.8);
                                                        return (tcm * $t29257_i5197);
                                                      }
                                                    })();
                                                    return (2.8 + $t29258_i5198);
                                                  }
                                                })();
                                                {
                                                  const sm = (() => {
                                                    {
                                                      const $t29258_i5193 = (() => {
                                                        {
                                                          const $t29257_i5192 = (1.6 - 0.7);
                                                          return (tsm * $t29257_i5192);
                                                        }
                                                      })();
                                                      return (0.7 + $t29258_i5193);
                                                    }
                                                  })();
                                                  {
                                                    const cap = (r * cm);
                                                    {
                                                      const $t29300 = (() => {
                                                        {
                                                          const $t29259_i5187 = (trings < 0.55);
                                                          if ($t29259_i5187 === true) {
                                                            return 1;
                                                          } else {
                                                            return (() => {
                                                              {
                                                                const $t29260_i5188 = (trings < 0.85);
                                                                if ($t29260_i5188 === true) {
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
                                                        const orbits = Perihelion$Level$make_orbits(cap, sm, $t29300);
                                                        {
                                                          const s = (() => {
                                                            {
                                                              const $t29302 = (() => {
                                                                {
                                                                  const $t29301 = prev.y;
                                                                  return ($t29301 - gap);
                                                                }
                                                              })();
                                                              return ({ x: x, y: $t29302, radius: r, capture_radius: cap, speed_mult: sm, orbits: orbits });
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
        const $t29309 = (view_w / 2.);
        {
          const $t29310 = ({ radius: 54., speed_mult: 1. });
          {
            const $t29311 = { $: "Nil" };
            {
              const $t29312 = { $: "Cons", _0: $t29310, _1: $t29311 };
              return ({ x: $t29309, y: 520., radius: 18., capture_radius: 54., speed_mult: 1., orbits: $t29312 });
            }
          }
        }
      }
    })();
    {
      const $p29317 = Perihelion$Level$next_star(rng, first, view_w);
      {
        const s2 = $p29317._0;
        {
          const rng2 = $p29317._1;
          {
            const $p29316 = Perihelion$Level$next_star(rng2, s2, view_w);
            {
              const s3 = $p29316._0;
              {
                const rng3 = $p29316._1;
                {
                  const $t29313 = { $: "Nil" };
                  {
                    const $t29314 = { $: "Cons", _0: s3, _1: $t29313 };
                    {
                      const $t29315 = { $: "Cons", _0: s2, _1: $t29314 };
                      {
                        const stars = { $: "Cons", _0: first, _1: $t29315 };
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
    const $t29329 = (() => {
      {
        const $t29327 = (() => {
          {
            const x_i5310 = (() => {
              {
                const $t29323_i5309 = (() => {
                  {
                    const $t29322_i5308 = (() => {
                      {
                        const $t29320_i5306 = (() => {
                          {
                            const $t29318_i5304 = (sx * 12.9898);
                            {
                              const $t29319_i5305 = (sy * 78.233);
                              return ($t29318_i5304 + $t29319_i5305);
                            }
                          }
                        })();
                        {
                          const $t29321_i5307 = (seed * 37.719);
                          return ($t29320_i5306 + $t29321_i5307);
                        }
                      }
                    })();
                    return Math.sin($t29322_i5308);
                  }
                })();
                return ($t29323_i5309 * 43758.5453);
              }
            })();
            {
              const $t29324_i5311 = (() => {
                {
                  const $t1603_i12235 = Math.floor(x_i5310);
                  return $t1603_i12235;
                }
              })();
              return (x_i5310 - $t29324_i5311);
            }
          }
        })();
        return ($t29327 > 0.55);
      }
    })();
    if ($t29329 === true) {
      return { $: "None" };
    } else {
      return (() => {
        {
          const jx = (() => {
            {
              const $t29333 = (() => {
                {
                  const $t29332 = (() => {
                    {
                      const $t29331 = (() => {
                        {
                          const $t29330 = (sx + 1.);
                          {
                            const x_i5299 = (() => {
                              {
                                const $t29323_i5298 = (() => {
                                  {
                                    const $t29322_i5297 = (() => {
                                      {
                                        const $t29320_i5295 = (() => {
                                          {
                                            const $t29318_i5293 = ($t29330 * 12.9898);
                                            {
                                              const $t29319_i5294 = (sy * 78.233);
                                              return ($t29318_i5293 + $t29319_i5294);
                                            }
                                          }
                                        })();
                                        {
                                          const $t29321_i5296 = (seed * 37.719);
                                          return ($t29320_i5295 + $t29321_i5296);
                                        }
                                      }
                                    })();
                                    return Math.sin($t29322_i5297);
                                  }
                                })();
                                return ($t29323_i5298 * 43758.5453);
                              }
                            })();
                            {
                              const $t29324_i5300 = (() => {
                                {
                                  const $t1603_i12232 = Math.floor(x_i5299);
                                  return $t1603_i12232;
                                }
                              })();
                              return (x_i5299 - $t29324_i5300);
                            }
                          }
                        }
                      })();
                      return ($t29331 - 0.5);
                    }
                  })();
                  return ($t29332 * 2.);
                }
              })();
              return ($t29333 * 90.);
            }
          })();
          {
            const jy = (() => {
              {
                const $t29338 = (() => {
                  {
                    const $t29337 = (() => {
                      {
                        const $t29336 = (() => {
                          {
                            const $t29335 = (sy + 1.);
                            {
                              const x_i5288 = (() => {
                                {
                                  const $t29323_i5287 = (() => {
                                    {
                                      const $t29322_i5286 = (() => {
                                        {
                                          const $t29320_i5284 = (() => {
                                            {
                                              const $t29318_i5282 = (sx * 12.9898);
                                              {
                                                const $t29319_i5283 = ($t29335 * 78.233);
                                                return ($t29318_i5282 + $t29319_i5283);
                                              }
                                            }
                                          })();
                                          {
                                            const $t29321_i5285 = (seed * 37.719);
                                            return ($t29320_i5284 + $t29321_i5285);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29322_i5286);
                                    }
                                  })();
                                  return ($t29323_i5287 * 43758.5453);
                                }
                              })();
                              {
                                const $t29324_i5289 = (() => {
                                  {
                                    const $t1603_i12229 = Math.floor(x_i5288);
                                    return $t1603_i12229;
                                  }
                                })();
                                return (x_i5288 - $t29324_i5289);
                              }
                            }
                          }
                        })();
                        return ($t29336 - 0.5);
                      }
                    })();
                    return ($t29337 * 2.);
                  }
                })();
                return ($t29338 * 90.);
              }
            })();
            {
              const rt = (() => {
                {
                  const $t29340 = (sx + 2.);
                  {
                    const x_i5277 = (() => {
                      {
                        const $t29323_i5276 = (() => {
                          {
                            const $t29322_i5275 = (() => {
                              {
                                const $t29320_i5273 = (() => {
                                  {
                                    const $t29318_i5271 = ($t29340 * 12.9898);
                                    {
                                      const $t29319_i5272 = (sy * 78.233);
                                      return ($t29318_i5271 + $t29319_i5272);
                                    }
                                  }
                                })();
                                {
                                  const $t29321_i5274 = (seed * 37.719);
                                  return ($t29320_i5273 + $t29321_i5274);
                                }
                              }
                            })();
                            return Math.sin($t29322_i5275);
                          }
                        })();
                        return ($t29323_i5276 * 43758.5453);
                      }
                    })();
                    {
                      const $t29324_i5278 = (() => {
                        {
                          const $t1603_i12226 = Math.floor(x_i5277);
                          return $t1603_i12226;
                        }
                      })();
                      return (x_i5277 - $t29324_i5278);
                    }
                  }
                }
              })();
              {
                const r = (() => {
                  {
                    const $t29343 = (rt * rt);
                    {
                      const $t29326_i5267 = (() => {
                        {
                          const $t29325_i5266 = (700. - 240.);
                          return ($t29343 * $t29325_i5266);
                        }
                      })();
                      return (240. + $t29326_i5267);
                    }
                  }
                })();
                {
                  const strength = (() => {
                    {
                      const $t29346 = (() => {
                        {
                          const $t29345 = (() => {
                            {
                              const $t29344 = (sy + 2.);
                              {
                                const x_i5261 = (() => {
                                  {
                                    const $t29323_i5260 = (() => {
                                      {
                                        const $t29322_i5259 = (() => {
                                          {
                                            const $t29320_i5257 = (() => {
                                              {
                                                const $t29318_i5255 = (sx * 12.9898);
                                                {
                                                  const $t29319_i5256 = ($t29344 * 78.233);
                                                  return ($t29318_i5255 + $t29319_i5256);
                                                }
                                              }
                                            })();
                                            {
                                              const $t29321_i5258 = (seed * 37.719);
                                              return ($t29320_i5257 + $t29321_i5258);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29322_i5259);
                                      }
                                    })();
                                    return ($t29323_i5260 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29324_i5262 = (() => {
                                    {
                                      const $t1603_i12223 = Math.floor(x_i5261);
                                      return $t1603_i12223;
                                    }
                                  })();
                                  return (x_i5261 - $t29324_i5262);
                                }
                              }
                            }
                          })();
                          return (0.65 * $t29345);
                        }
                      })();
                      return (0.35 + $t29346);
                    }
                  })();
                  {
                    const $t29349 = (() => {
                      {
                        const $t29347 = (sx + jx);
                        {
                          const $t29348 = (sy + jy);
                          return ({ x: $t29347, y: $t29348, radius: r, strength: strength });
                        }
                      }
                    })();
                    return { $: "Some", _0: $t29349 };
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
      const $f29382 = stars._0;
      const $f29383 = stars._1;
      {
        const rest = $f29383;
        {
          const s = $f29382;
          {
            const $t29380 = (() => {
              {
                const $t29378 = s.x;
                {
                  const $t29379 = s.y;
                  return Perihelion$Nebula$star_cloud($t29378, $t29379, seed);
                }
              }
            })();
            {
              let acc2;
              switch ($t29380.$) {
                case "None": {
                  acc2 = acc;
                  break;
                }
                case "Some": {
                  const $f29381 = $t29380._0;
                  acc2 = (() => {
                    {
                      const c = $f29381;
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
      const $f29396 = stars._0;
      const $f29397 = stars._1;
      {
        const rest = $f29397;
        {
          const s = $f29396;
          {
            const $t29395 = (() => {
              {
                const $t29390_i5344 = (() => {
                  {
                    const $t29388_i5342 = s.y;
                    {
                      const $t29389_i5343 = (cam_y - margin);
                      return ($t29388_i5342 >= $t29389_i5343);
                    }
                  }
                })();
                {
                  const $t29394_i5348 = (() => {
                    {
                      const $t29391_i5345 = s.y;
                      {
                        const $t29393_i5347 = (() => {
                          {
                            const $t29392_i5346 = (cam_y + view_h);
                            return ($t29392_i5346 + margin);
                          }
                        })();
                        return ($t29391_i5345 <= $t29393_i5347);
                      }
                    }
                  })();
                  return ($t29390_i5344 && $t29394_i5348);
                }
              }
            })();
            {
              let acc2;
              if ($t29395 === true) {
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
    const $t29407 = (stars_chained > 0);
    {
      const $t29410 = (() => {
        {
          const $t29409 = march_int_mod(stars_chained, 10);
          return ($t29409 === 0);
        }
      })();
      return ($t29407 && $t29410);
    }
  }
}
const Perihelion$Upgrades$is_milestone$clo = { _0: ($_, stars_chained) => Perihelion$Upgrades$is_milestone(stars_chained) };

function Perihelion$Upgrades$milestone_pool(owned) {
  {
    const $t29412 = (() => {
      {
        const $t29411 = { $: "Homing" };
        return { $: "OffenseWeapon", _0: $t29411 };
      }
    })();
    {
      const $t29414 = (() => {
        {
          const $t29413 = { $: "Spread" };
          return { $: "OffenseWeapon", _0: $t29413 };
        }
      })();
      {
        const $t29415 = { $: "Nil" };
        {
          const $t29416 = { $: "Cons", _0: $t29414, _1: $t29415 };
          {
            const all_weapons = { $: "Cons", _0: $t29412, _1: $t29416 };
            {
              const $t29420 = { $: "$Clo_$lam29417$3803", _0: $lam29417$apply$3803, _1: owned };
              {
                const unowned_weapons = (() => {
                  {
                    const pred_i5355 = $t29420;
                    {
                      const go_i5356 = { $: "$Clo_go$4809", _0: go$apply$4809, _1: pred_i5355 };
                      {
                        const $t323_i5357 = { $: "Nil" };
                        return go$apply$4809(go_i5356, all_weapons, $t323_i5357);
                      }
                    }
                  }
                })();
                {
                  const $t29421 = { $: "OffenseFireRate" };
                  {
                    const $t29422 = { $: "DefenseBulletWard" };
                    {
                      const $t29423 = { $: "DefenseDeflector" };
                      {
                        const $t29424 = { $: "DefenseShield" };
                        {
                          const $t29426 = (() => {
                            {
                              const $t29425 = { $: "StarThrust" };
                              return { $: "SpecialItem", _0: $t29425 };
                            }
                          })();
                          {
                            const $t29428 = (() => {
                              {
                                const $t29427 = { $: "StarJump" };
                                return { $: "SpecialItem", _0: $t29427 };
                              }
                            })();
                            {
                              const $t29430 = (() => {
                                {
                                  const $t29429 = { $: "TrajectoryPreview" };
                                  return { $: "SpecialItem", _0: $t29429 };
                                }
                              })();
                              {
                                const $t29431 = { $: "Nil" };
                                {
                                  const $t29432 = { $: "Cons", _0: $t29430, _1: $t29431 };
                                  {
                                    const $t29433 = { $: "Cons", _0: $t29428, _1: $t29432 };
                                    {
                                      const $t29434 = { $: "Cons", _0: $t29426, _1: $t29433 };
                                      {
                                        const $t29435 = { $: "Cons", _0: $t29424, _1: $t29434 };
                                        {
                                          const $t29436 = { $: "Cons", _0: $t29423, _1: $t29435 };
                                          {
                                            const $t29437 = { $: "Cons", _0: $t29422, _1: $t29436 };
                                            {
                                              const $t29438 = { $: "Cons", _0: $t29421, _1: $t29437 };
                                              {
                                                const go_i5352 = { $: "$Clo_go$4807", _0: go$apply$4807 };
                                                {
                                                  const $t282_i5353 = (() => {
                                                    {
                                                      const go_i12238 = { $: "$Clo_go$5263", _0: go$apply$5263 };
                                                      {
                                                        const $t274_i12239 = { $: "Nil" };
                                                        return go$apply$5263(go_i12238, unowned_weapons, $t274_i12239);
                                                      }
                                                    }
                                                  })();
                                                  return go$apply$4807(go_i5352, $t282_i5353, $t29438);
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
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
    const $t29439 = (() => {
      {
        const go_i5364 = { $: "$Clo_go$4812", _0: go$apply$4812 };
        {
          const $t529_i5365 = { $: "Nil" };
          return go$apply$4812(go_i5364, xs, idx, $t529_i5365);
        }
      }
    })();
    {
      const $t29440 = (idx + 1);
      {
        const $t29441 = List$drop$List_UpgradeKind$Int(xs, $t29440);
        {
          const go_i5360 = { $: "$Clo_go$4807", _0: go$apply$4807 };
          {
            const $t282_i5361 = (() => {
              {
                const go_i12241 = { $: "$Clo_go$5263", _0: go$apply$5263 };
                {
                  const $t274_i12242 = { $: "Nil" };
                  return go$apply$5263(go_i12241, $t29439, $t274_i12242);
                }
              }
            })();
            return go$apply$4807(go_i5360, $t282_i5361, $t29441);
          }
        }
      }
    }
  }
}
const Perihelion$Upgrades$remove_upgrade_at$clo = { _0: ($_, xs, idx) => Perihelion$Upgrades$remove_upgrade_at(xs, idx) };

function Perihelion$Upgrades$pick_and_remove(rng, pool) {
  {
    const $p29445 = (() => {
      {
        const $p29256_i5182_i12244 = (() => {
          {
            const $p15861_i12797 = (() => {
              {
                const $p15858_i1974_i12788 = Random$next_raw(rng);
                {
                  const hi_i1975_i12789 = $p15858_i1974_i12788._0;
                  {
                    const rng2_i1976_i12790 = $p15858_i1974_i12788._1;
                    {
                      const $p15857_i1977_i12791 = Random$next_raw(rng2_i1976_i12790);
                      {
                        const lo_i1978_i12792 = $p15857_i1977_i12791._0;
                        {
                          const rng3_i1979_i12793 = $p15857_i1977_i12791._1;
                          {
                            const $t15856_i1983_i12796 = (() => {
                              {
                                const $t15855_i1982_i12795 = (() => {
                                  {
                                    const $t15853_i1980_i12794 = march_int_and(hi_i1975_i12789, 1048575);
                                    return ($t15853_i1980_i12794 * 4294967296);
                                  }
                                })();
                                return ($t15855_i1982_i12795 + lo_i1978_i12792);
                              }
                            })();
                            return { _0: $t15856_i1983_i12796, _1: rng3_i1979_i12793 };
                          }
                        }
                      }
                    }
                  }
                }
              }
            })();
            {
              const bits_i12798 = $p15861_i12797._0;
              {
                const rng2_i12799 = $p15861_i12797._1;
                {
                  const $t15860_i12801 = (() => {
                    {
                      const $t15859_i12800 = bits_i12798;
                      return ($t15859_i12800 / 4.50359962737e+15);
                    }
                  })();
                  return { _0: $t15860_i12801, _1: rng2_i12799 };
                }
              }
            }
          }
        })();
        {
          const t_i5183_i12245 = $p29256_i5182_i12244._0;
          {
            const rng2_i5184_i12246 = $p29256_i5182_i12244._1;
            {
              const out_i5185_i12247 = { _0: rng2_i5184_i12246, _1: t_i5183_i12245 };
              return out_i5185_i12247;
            }
          }
        }
      }
    })();
    {
      const rng2 = $p29445._0;
      {
        const t = $p29445._1;
        {
          const n = (() => {
            {
              const go_i5367 = { $: "$Clo_go$4815", _0: go$apply$4815 };
              return go$apply$4815(go_i5367, pool, 0);
            }
          })();
          {
            const idx = (() => {
              {
                const $t29443 = (() => {
                  {
                    const $t29442 = n;
                    return (t * $t29442);
                  }
                })();
                return Math.trunc($t29443);
              }
            })();
            {
              const clamped = (() => {
                {
                  const $t29444 = (idx >= n);
                  if ($t29444 === true) {
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
    const $t29448 = (() => {
      {
        const $t29446 = (n === 0);
        {
          let $t29447;
          switch (pool.$) {
            case "Nil": {
              $t29447 = true;
              break;
            }
            default: {
              $t29447 = false;
              break;
            }
          }
          return ($t29446 || $t29447);
        }
      }
    })();
    if ($t29448 === true) {
      return { _0: rng, _1: acc };
    } else {
      return (() => {
        {
          const $p29451 = Perihelion$Upgrades$pick_and_remove(rng, pool);
          {
            const rng2 = $p29451._0;
            {
              const picked = $p29451._1;
              {
                const rest = $p29451._2;
                {
                  const $t29449 = (n - 1);
                  {
                    const $t29450 = (() => {
                      return { $: "Cons", _0: picked, _1: acc };
                    })();
                    return Perihelion$Upgrades$draw_n(rng2, rest, $t29449, $t29450);
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
        const $t29452 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        {
          const $t29453 = { $: "Nil" };
          return Perihelion$Upgrades$draw_n(rng, $t29452, 3, $t29453);
        }
      }
      break;
    }
    case "Some": {
      const $f29462 = current_special._0;
      {
        const k = $f29462;
        {
          const $t29454 = Perihelion$Upgrades$milestone_pool(owned_weapons);
          {
            const $t29457 = (() => {
              return { $: "$Clo_$lam29455$3804", _0: $lam29455$apply$3804, _1: k };
            })();
            {
              const pool = (() => {
                {
                  const pred_i5372 = $t29457;
                  {
                    const go_i5373 = { $: "$Clo_go$4809", _0: go$apply$4809, _1: pred_i5372 };
                    {
                      const $t323_i5374 = { $: "Nil" };
                      return go$apply$4809(go_i5373, $t29454, $t323_i5374);
                    }
                  }
                }
              })();
              {
                const $p29461 = (() => {
                  {
                    const $t29458 = { $: "Nil" };
                    return Perihelion$Upgrades$draw_n(rng, pool, 2, $t29458);
                  }
                })();
                {
                  const rng2 = $p29461._0;
                  {
                    const two = $p29461._1;
                    {
                      const $t29459 = { $: "SpecialItem", _0: k };
                      {
                        const $t29460 = (() => {
                          return { $: "Cons", _0: $t29459, _1: two };
                        })();
                        return { _0: rng2, _1: $t29460 };
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
    const $p29464 = (() => {
      {
        const $t29463 = Perihelion$Upgrades$milestone_pool(owned_weapons);
        return Perihelion$Upgrades$pick_and_remove(rng, $t29463);
      }
    })();
    {
      const rng2 = $p29464._0;
      {
        const picked = $p29464._1;
        return { _0: rng2, _1: picked };
      }
    }
  }
}
const Perihelion$Upgrades$roll_one$clo = { _0: ($_, rng, owned_weapons, current_special) => Perihelion$Upgrades$roll_one(rng, owned_weapons, current_special) };

function boot_seed() {
  {
    const $t29467 = (() => {
      {
        const $t29466 = (() => {
          {
            const $t29465 = {  };
            return march_unix_time();
          }
        })();
        return ($t29466 * 1000000.);
      }
    })();
    return Math.trunc($t29467);
  }
}
const boot_seed$clo = { _0: ($_) => boot_seed() };

function spawn_burst_particles(x, y, t, i, acc) {
  {
    const $t29478 = (i >= 10);
    if ($t29478 === true) {
      return acc;
    } else {
      return (() => {
        {
          const seed = (() => {
            {
              const $t29480 = (() => {
                {
                  const $t29479 = i;
                  return ($t29479 * 7.);
                }
              })();
              return (t + $t29480);
            }
          })();
          {
            const a = (() => {
              {
                const $t29481 = (() => {
                  {
                    const x_i5402 = (() => {
                      {
                        const $t29475_i5401 = (() => {
                          {
                            const $t29474_i5400 = (() => {
                              {
                                const $t29472_i5398 = (seed * 12.9898);
                                {
                                  const $t29473_i5399 = (1. * 78.233);
                                  return ($t29472_i5398 + $t29473_i5399);
                                }
                              }
                            })();
                            return Math.sin($t29474_i5400);
                          }
                        })();
                        return ($t29475_i5401 * 43758.5453);
                      }
                    })();
                    {
                      const $t29476_i5403 = (() => {
                        {
                          const $t1603_i12255 = Math.floor(x_i5402);
                          return $t1603_i12255;
                        }
                      })();
                      return (x_i5402 - $t29476_i5403);
                    }
                  }
                })();
                return ($t29481 * 6.28318530718);
              }
            })();
            {
              const speed = (() => {
                {
                  const $t29484 = (() => {
                    {
                      const $t29483 = (() => {
                        {
                          const x_i5394 = (() => {
                            {
                              const $t29475_i5393 = (() => {
                                {
                                  const $t29474_i5392 = (() => {
                                    {
                                      const $t29472_i5390 = (seed * 12.9898);
                                      {
                                        const $t29473_i5391 = (2. * 78.233);
                                        return ($t29472_i5390 + $t29473_i5391);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29474_i5392);
                                }
                              })();
                              return ($t29475_i5393 * 43758.5453);
                            }
                          })();
                          {
                            const $t29476_i5395 = (() => {
                              {
                                const $t1603_i12252 = Math.floor(x_i5394);
                                return $t1603_i12252;
                              }
                            })();
                            return (x_i5394 - $t29476_i5395);
                          }
                        }
                      })();
                      return ($t29483 * 90.);
                    }
                  })();
                  return (40. + $t29484);
                }
              })();
              {
                const life = (() => {
                  {
                    const $t29488 = (() => {
                      {
                        const $t29487 = (() => {
                          {
                            const $t29486 = (() => {
                              {
                                const x_i5386 = (() => {
                                  {
                                    const $t29475_i5385 = (() => {
                                      {
                                        const $t29474_i5384 = (() => {
                                          {
                                            const $t29472_i5382 = (seed * 12.9898);
                                            {
                                              const $t29473_i5383 = (3. * 78.233);
                                              return ($t29472_i5382 + $t29473_i5383);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29474_i5384);
                                      }
                                    })();
                                    return ($t29475_i5385 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29476_i5387 = (() => {
                                    {
                                      const $t1603_i12249 = Math.floor(x_i5386);
                                      return $t1603_i12249;
                                    }
                                  })();
                                  return (x_i5386 - $t29476_i5387);
                                }
                              }
                            })();
                            return (0.4 * $t29486);
                          }
                        })();
                        return (0.6 + $t29487);
                      }
                    })();
                    return (0.5 * $t29488);
                  }
                })();
                {
                  const p = (() => {
                    {
                      const $t29490 = (() => {
                        {
                          const $t29489 = Math.cos(a);
                          return ($t29489 * speed);
                        }
                      })();
                      {
                        const $t29492 = (() => {
                          {
                            const $t29491 = Math.sin(a);
                            return ($t29491 * speed);
                          }
                        })();
                        return ({ x: x, y: y, vx: $t29490, vy: $t29492, life: life, max_life: life });
                      }
                    }
                  })();
                  {
                    const $t29493 = (i + 1);
                    {
                      const $t29494 = { $: "Cons", _0: p, _1: acc };
                      return spawn_burst_particles(x, y, t, $t29493, $t29494);
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
      const $f29497 = bursts._0;
      const $f29498 = bursts._1;
      {
        const rest = (() => {
          return $f29498;
        })();
        {
          const pt = (() => {
            return $f29497;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const $t29495 = spawn_burst_particles(x, y, t, 0, acc);
                return spawn_bursts(rest, t, $t29495);
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
      const $f29524 = flash._0;
      {
        const f = $f29524;
        {
          const x = f._0;
          {
            const y = f._1;
            {
              const tr = f._2;
              {
                const tr2 = (tr - dt_s);
                {
                  const $t29521 = (tr2 > 0.);
                  if ($t29521 === true) {
                    return (() => {
                      {
                        const $t29522 = { _0: x, _1: y, _2: tr2 };
                        return { $: "Some", _0: $t29522 };
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
        const $t29525 = fx.t;
        return ($t29525 + dt_s);
      }
    })();
    {
      const $t29526 = (() => {
        {
          const $t30095_i5429 = game.phase;
          switch ($t30095_i5429.$) {
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
        if ($t29526 === true) {
          trail2 = (() => {
            {
              const $t29527 = fx.trail;
              {
                const $t29528 = game.ball_x;
                {
                  const $t29529 = game.ball_y;
                  {
                    const $t29530 = { _0: $t29528, _1: $t29529 };
                    {
                      const $t29519_i5426 = { $: "Cons", _0: $t29530, _1: $t29527 };
                      {
                        const go_i12267 = { $: "$Clo_go$4821", _0: go$apply$4821 };
                        {
                          const $t529_i12268 = { $: "Nil" };
                          return go$apply$4821(go_i12267, $t29519_i5426, 14, $t529_i12268);
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
          const $t29531 = game.fx_bursts;
          {
            const $t29532 = fx.particles;
            {
              const $t29533 = (() => {
                return spawn_bursts($t29531, t2, $t29532);
              })();
              {
                const particles2 = (() => {
                  {
                    const $t29514_i5421 = { $: "$Clo_$lam29513$3806", _0: $lam29513$apply$3806, _1: dt_s };
                    {
                      const $t29515_i5422 = (() => {
                        {
                          const f_i12262 = $t29514_i5421;
                          {
                            const go_i12263 = { $: "$Clo_go$4819", _0: go$apply$4819, _1: f_i12262 };
                            {
                              const $t291_i12264 = { $: "Nil" };
                              return go$apply$4819(go_i12263, $t29533, $t291_i12264);
                            }
                          }
                        }
                      })();
                      {
                        const $t29518_i5423 = { $: "$Clo_$lam29516$3807", _0: $lam29516$apply$3807 };
                        {
                          const pred_i12258 = $t29518_i5423;
                          {
                            const go_i12259 = { $: "$Clo_go$4817", _0: go$apply$4817, _1: pred_i12258 };
                            {
                              const $t323_i12260 = { $: "Nil" };
                              return go$apply$4817(go_i12259, $t29515_i5422, $t323_i12260);
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
                      const $t29534 = fx.flash;
                      return step_flash($t29534, dt_s);
                    }
                  })();
                  {
                    const flash2 = (() => {
                      {
                        const $t29535 = game.capture_flash;
                        switch ($t29535.$) {
                          case "None": {
                            return flash1;
                            break;
                          }
                          case "Some": {
                            const $f29539 = $t29535._0;
                            {
                              const pt = (() => {
                                return $f29539;
                              })();
                              {
                                const x = pt._0;
                                {
                                  const y = pt._1;
                                  {
                                    const $t29537 = { _0: x, _1: y, _2: 0.45 };
                                    return { $: "Some", _0: $t29537 };
                                  }
                                }
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
      const $f29549 = trail._0;
      const $f29550 = trail._1;
      {
        const rest = (() => {
          return $f29550;
        })();
        {
          const pt = (() => {
            return $f29549;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              {
                const f = (() => {
                  {
                    const $t29542 = (() => {
                      {
                        const $t29540 = i;
                        {
                          const $t29541 = n;
                          return ($t29540 / $t29541);
                        }
                      }
                    })();
                    return (1. - $t29542);
                  }
                })();
                (() => {
                  {
                    const $t29543 = (f * 0.28);
                    return Canvas$set_global_alpha(ctx, $t29543);
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
                    const $t29545 = (() => {
                      {
                        const $t29544 = (2.5 * f);
                        return (1. + $t29544);
                      }
                    })();
                    return Canvas$arc(ctx, x, y, $t29545, 0., 6.28318530718);
                  }
                })();
                (() => {
                  return Canvas$fill(ctx);
                })();
                {
                  const $t29547 = (i + 1);
                  return draw_trail(ctx, rest, $t29547, n);
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
      const $f29562 = particles._0;
      const $f29563 = particles._1;
      {
        const rest = (() => {
          return $f29563;
        })();
        {
          const p = (() => {
            return $f29562;
          })();
          {
            const f = (() => {
              {
                const $t29555 = p.life;
                {
                  const $t29556 = p.max_life;
                  return ($t29555 / $t29556);
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
                const $t29557 = p.x;
                {
                  const $t29558 = p.y;
                  {
                    const $t29560 = (() => {
                      {
                        const $t29559 = (1.5 * f);
                        return (0.5 + $t29559);
                      }
                    })();
                    return Canvas$arc(ctx, $t29557, $t29558, $t29560, 0., 6.28318530718);
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
      const $f29578 = flash._0;
      {
        const f = (() => {
          return $f29578;
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
                    const $t29569 = (tr / 0.45);
                    return (1. - $t29569);
                  }
                })();
                {
                  const r = (() => {
                    {
                      const $t29570 = (prog * 60.);
                      return (8. + $t29570);
                    }
                  })();
                  (() => {
                    {
                      const $t29572 = (() => {
                        {
                          const $t29571 = (1. - prog);
                          return ($t29571 * 0.7);
                        }
                      })();
                      return Canvas$set_global_alpha(ctx, $t29572);
                    }
                  })();
                  (() => {
                    return Canvas$set_stroke_style(ctx, "#ffffff");
                  })();
                  (() => {
                    {
                      const $t29575 = (() => {
                        {
                          const $t29574 = (() => {
                            {
                              const $t29573 = (1. - prog);
                              return (2.5 * $t29573);
                            }
                          })();
                          return ($t29574 + 0.5);
                        }
                      })();
                      return Canvas$set_line_width(ctx, $t29575);
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
      const $t29613 = (0.1 * pulse);
      return Canvas$set_global_alpha(ctx, $t29613);
    }
  })();
  (() => {
    return Canvas$set_stroke_style(ctx, "#cfcfcf");
  })();
  (() => {
    {
      const $t29615 = (() => {
        {
          const $t29614 = (0.6 * pulse);
          return (1. + $t29614);
        }
      })();
      return Canvas$set_line_width(ctx, $t29615);
    }
  })();
  (() => {
    return Canvas$begin_path(ctx);
  })();
  (() => {
    {
      const $t29616 = s.x;
      {
        const $t29617 = s.y;
        {
          const $t29618 = s.capture_radius;
          return Canvas$arc(ctx, $t29616, $t29617, $t29618, 0., 6.28318530718);
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
      const $t29621 = (() => {
        {
          const $t29620 = (0.035 * pulse);
          return (0.025 + $t29620);
        }
      })();
      return Canvas$set_global_alpha(ctx, $t29621);
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
      const $t29622 = s.x;
      {
        const $t29623 = s.y;
        {
          const $t29627 = (() => {
            {
              const $t29624 = s.radius;
              {
                const $t29626 = (() => {
                  {
                    const $t29625 = (0.9 * pulse);
                    return (1.6 + $t29625);
                  }
                })();
                return ($t29624 * $t29626);
              }
            }
          })();
          return Canvas$arc(ctx, $t29622, $t29623, $t29627, 0., 6.28318530718);
        }
      }
    }
  })();
  return Canvas$fill(ctx);
}
const draw_pulse_halo$clo = { _0: ($_, ctx, s, pulse) => draw_pulse_halo(ctx, s, pulse) };

function draw_pulse_particle(ctx, s, t, n, i) {
  {
    const $t29629 = (i >= n);
    if ($t29629 === true) {
      return {  };
    } else {
      return (() => {
        {
          const a = (() => {
            {
              const $t29633 = (() => {
                {
                  const $t29631 = (() => {
                    {
                      const $t29630 = (() => {
                        {
                          const $t29612_i5496 = (() => {
                            {
                              const $t29611_i5495 = (() => {
                                {
                                  const $t29608_i5492 = (() => {
                                    {
                                      const $t29607_i5491 = s.x;
                                      return ($t29607_i5491 + 5.);
                                    }
                                  })();
                                  {
                                    const $t29610_i5494 = (() => {
                                      {
                                        const $t29609_i5493 = s.y;
                                        return ($t29609_i5493 + 5.);
                                      }
                                    })();
                                    {
                                      const x_i12284 = (() => {
                                        {
                                          const $t29475_i12283 = (() => {
                                            {
                                              const $t29474_i12282 = (() => {
                                                {
                                                  const $t29472_i12280 = ($t29608_i5492 * 12.9898);
                                                  {
                                                    const $t29473_i12281 = ($t29610_i5494 * 78.233);
                                                    return ($t29472_i12280 + $t29473_i12281);
                                                  }
                                                }
                                              })();
                                              return Math.sin($t29474_i12282);
                                            }
                                          })();
                                          return ($t29475_i12283 * 43758.5453);
                                        }
                                      })();
                                      {
                                        const $t29476_i12286 = (() => {
                                          {
                                            const $t1603_i5376_i12285 = Math.floor(x_i12284);
                                            return $t1603_i5376_i12285;
                                          }
                                        })();
                                        return (x_i12284 - $t29476_i12286);
                                      }
                                    }
                                  }
                                }
                              })();
                              return ($t29611_i5495 * 2.4);
                            }
                          })();
                          return (0.4 + $t29612_i5496);
                        }
                      })();
                      return (t * $t29630);
                    }
                  })();
                  {
                    const $t29632 = (() => {
                      {
                        const $t29598_i5488 = (() => {
                          {
                            const $t29595_i5485 = (() => {
                              {
                                const $t29594_i5484 = s.x;
                                return ($t29594_i5484 + 3.);
                              }
                            })();
                            {
                              const $t29597_i5487 = (() => {
                                {
                                  const $t29596_i5486 = s.y;
                                  return ($t29596_i5486 + 3.);
                                }
                              })();
                              {
                                const x_i12275 = (() => {
                                  {
                                    const $t29475_i12274 = (() => {
                                      {
                                        const $t29474_i12273 = (() => {
                                          {
                                            const $t29472_i12271 = ($t29595_i5485 * 12.9898);
                                            {
                                              const $t29473_i12272 = ($t29597_i5487 * 78.233);
                                              return ($t29472_i12271 + $t29473_i12272);
                                            }
                                          }
                                        })();
                                        return Math.sin($t29474_i12273);
                                      }
                                    })();
                                    return ($t29475_i12274 * 43758.5453);
                                  }
                                })();
                                {
                                  const $t29476_i12277 = (() => {
                                    {
                                      const $t1603_i5376_i12276 = Math.floor(x_i12275);
                                      return $t1603_i5376_i12276;
                                    }
                                  })();
                                  return (x_i12275 - $t29476_i12277);
                                }
                              }
                            }
                          }
                        })();
                        return ($t29598_i5488 * 6.28318530718);
                      }
                    })();
                    return ($t29631 + $t29632);
                  }
                }
              })();
              {
                const $t29638 = (() => {
                  {
                    const $t29634 = i;
                    {
                      const $t29637 = (() => {
                        {
                          const $t29636 = n;
                          return (6.28318530718 / $t29636);
                        }
                      })();
                      return ($t29634 * $t29637);
                    }
                  }
                })();
                return ($t29633 + $t29638);
              }
            }
          })();
          {
            const r = (() => {
              {
                const $t29639 = s.radius;
                return ($t29639 * 1.8);
              }
            })();
            {
              const px = (() => {
                {
                  const $t29640 = s.x;
                  {
                    const $t29642 = (() => {
                      {
                        const $t29641 = Math.cos(a);
                        return ($t29641 * r);
                      }
                    })();
                    return ($t29640 + $t29642);
                  }
                }
              })();
              {
                const py = (() => {
                  {
                    const $t29643 = s.y;
                    {
                      const $t29645 = (() => {
                        {
                          const $t29644 = Math.sin(a);
                          return ($t29644 * r);
                        }
                      })();
                      return ($t29643 + $t29645);
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
                  const $t29647 = (i + 1);
                  return draw_pulse_particle(ctx, s, t, n, $t29647);
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
      const $f29656 = orbits._0;
      const $f29657 = orbits._1;
      {
        const $jp_clo29663 = (() => {
          return { $: "$Clo_$jp29662$3810", _0: $jp29662$apply$3810, _1: $f29656, _2: $f29657, _3: ctx, _4: s };
        })();
        switch ($f29657.$) {
          case "Nil": {
            {
              const o = $f29656;
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
                  const $t29648 = s.x;
                  {
                    const $t29649 = s.y;
                    {
                      const $t29650 = o.radius;
                      return Canvas$arc(ctx, $t29648, $t29649, $t29650, 0., 6.28318530718);
                    }
                  }
                }
              })();
              return Canvas$stroke(ctx);
            }
            break;
          }
          default: {
            return $jp29662$apply$3810($jp_clo29663);
          }
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
      const $f29679 = aim._0;
      {
        const a = (() => {
          return $f29679;
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
                      const $t29666 = s.x;
                      return ($t29666 - px);
                    }
                  })();
                  {
                    const dy = (() => {
                      {
                        const $t29667 = s.y;
                        return ($t29667 - py);
                      }
                    })();
                    {
                      const range = (() => {
                        {
                          const $t29668 = s.capture_radius;
                          return ($t29668 * 4.);
                        }
                      })();
                      {
                        const $t29672 = (() => {
                          {
                            const $t29671 = (() => {
                              {
                                const $t29669 = (vx * dx);
                                {
                                  const $t29670 = (vy * dy);
                                  return ($t29669 + $t29670);
                                }
                              }
                            })();
                            return ($t29671 > 0.);
                          }
                        })();
                        {
                          const $t29677 = (() => {
                            {
                              const $t29675 = (() => {
                                {
                                  const $t29673 = (dx * dx);
                                  {
                                    const $t29674 = (dy * dy);
                                    return ($t29673 + $t29674);
                                  }
                                }
                              })();
                              {
                                const $t29676 = (range * range);
                                return ($t29675 < $t29676);
                              }
                            }
                          })();
                          return ($t29672 && $t29677);
                        }
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
        const $t29682 = (() => {
          {
            const $t29681 = (() => {
              {
                const $t29680 = (t * 6.);
                return Math.sin($t29680);
              }
            })();
            return (0.5 * $t29681);
          }
        })();
        return (0.5 + $t29682);
      }
    })();
    (() => {
      {
        const $t29684 = (() => {
          {
            const $t29683 = (0.45 * pulse);
            return (0.3 + $t29683);
          }
        })();
        return Canvas$set_global_alpha(ctx, $t29684);
      }
    })();
    (() => {
      return Canvas$set_stroke_style(ctx, "#ffffff");
    })();
    (() => {
      {
        const $t29686 = (() => {
          {
            const $t29685 = (1.6 * pulse);
            return (1.2 + $t29685);
          }
        })();
        return Canvas$set_line_width(ctx, $t29686);
      }
    })();
    (() => {
      return Canvas$begin_path(ctx);
    })();
    (() => {
      {
        const $t29687 = s.x;
        {
          const $t29688 = s.y;
          {
            const $t29689 = s.capture_radius;
            return Canvas$arc(ctx, $t29687, $t29688, $t29689, 0., 6.28318530718);
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
      const $t29691 = s.orbits;
      return draw_orbit_rings(ctx, s, $t29691);
    }
  })();
  (() => {
    {
      const $t29692 = (() => {
        {
          const $t29581_i5534 = (() => {
            {
              const $t29579_i5532 = s.x;
              {
                const $t29580_i5533 = s.y;
                {
                  const x_i12329 = (() => {
                    {
                      const $t29475_i12328 = (() => {
                        {
                          const $t29474_i12327 = (() => {
                            {
                              const $t29472_i12325 = ($t29579_i5532 * 12.9898);
                              {
                                const $t29473_i12326 = ($t29580_i5533 * 78.233);
                                return ($t29472_i12325 + $t29473_i12326);
                              }
                            }
                          })();
                          return Math.sin($t29474_i12327);
                        }
                      })();
                      return ($t29475_i12328 * 43758.5453);
                    }
                  })();
                  {
                    const $t29476_i12331 = (() => {
                      {
                        const $t1603_i5376_i12330 = Math.floor(x_i12329);
                        return $t1603_i5376_i12330;
                      }
                    })();
                    return (x_i12329 - $t29476_i12331);
                  }
                }
              }
            }
          })();
          return ($t29581_i5534 < 0.8);
        }
      })();
      if ($t29692 === true) {
        return (() => {
          {
            const pulse = (() => {
              {
                const $t29698 = (() => {
                  {
                    const $t29697 = (() => {
                      {
                        const $t29696 = (() => {
                          {
                            const $t29694 = (() => {
                              {
                                const $t29693 = (() => {
                                  {
                                    const $t29593_i5530 = (() => {
                                      {
                                        const $t29592_i5529 = (() => {
                                          {
                                            const $t29589_i5526 = (() => {
                                              {
                                                const $t29588_i5525 = s.x;
                                                return ($t29588_i5525 + 2.);
                                              }
                                            })();
                                            {
                                              const $t29591_i5528 = (() => {
                                                {
                                                  const $t29590_i5527 = s.y;
                                                  return ($t29590_i5527 + 2.);
                                                }
                                              })();
                                              {
                                                const x_i12320 = (() => {
                                                  {
                                                    const $t29475_i12319 = (() => {
                                                      {
                                                        const $t29474_i12318 = (() => {
                                                          {
                                                            const $t29472_i12316 = ($t29589_i5526 * 12.9898);
                                                            {
                                                              const $t29473_i12317 = ($t29591_i5528 * 78.233);
                                                              return ($t29472_i12316 + $t29473_i12317);
                                                            }
                                                          }
                                                        })();
                                                        return Math.sin($t29474_i12318);
                                                      }
                                                    })();
                                                    return ($t29475_i12319 * 43758.5453);
                                                  }
                                                })();
                                                {
                                                  const $t29476_i12322 = (() => {
                                                    {
                                                      const $t1603_i5376_i12321 = Math.floor(x_i12320);
                                                      return $t1603_i5376_i12321;
                                                    }
                                                  })();
                                                  return (x_i12320 - $t29476_i12322);
                                                }
                                              }
                                            }
                                          }
                                        })();
                                        return ($t29592_i5529 * 1.8);
                                      }
                                    })();
                                    return (0.6 + $t29593_i5530);
                                  }
                                })();
                                return (t * $t29693);
                              }
                            })();
                            {
                              const $t29695 = (() => {
                                {
                                  const $t29598_i5522 = (() => {
                                    {
                                      const $t29595_i5519 = (() => {
                                        {
                                          const $t29594_i5518 = s.x;
                                          return ($t29594_i5518 + 3.);
                                        }
                                      })();
                                      {
                                        const $t29597_i5521 = (() => {
                                          {
                                            const $t29596_i5520 = s.y;
                                            return ($t29596_i5520 + 3.);
                                          }
                                        })();
                                        {
                                          const x_i12311 = (() => {
                                            {
                                              const $t29475_i12310 = (() => {
                                                {
                                                  const $t29474_i12309 = (() => {
                                                    {
                                                      const $t29472_i12307 = ($t29595_i5519 * 12.9898);
                                                      {
                                                        const $t29473_i12308 = ($t29597_i5521 * 78.233);
                                                        return ($t29472_i12307 + $t29473_i12308);
                                                      }
                                                    }
                                                  })();
                                                  return Math.sin($t29474_i12309);
                                                }
                                              })();
                                              return ($t29475_i12310 * 43758.5453);
                                            }
                                          })();
                                          {
                                            const $t29476_i12313 = (() => {
                                              {
                                                const $t1603_i5376_i12312 = Math.floor(x_i12311);
                                                return $t1603_i5376_i12312;
                                              }
                                            })();
                                            return (x_i12311 - $t29476_i12313);
                                          }
                                        }
                                      }
                                    }
                                  })();
                                  return ($t29598_i5522 * 6.28318530718);
                                }
                              })();
                              return ($t29694 + $t29695);
                            }
                          }
                        })();
                        return Math.sin($t29696);
                      }
                    })();
                    return (0.5 * $t29697);
                  }
                })();
                return (0.5 + $t29698);
              }
            })();
            {
              const $t29699 = (() => {
                {
                  const r_i5513 = (() => {
                    {
                      const $t29583_i5510 = (() => {
                        {
                          const $t29582_i5509 = s.x;
                          return ($t29582_i5509 + 1.);
                        }
                      })();
                      {
                        const $t29585_i5512 = (() => {
                          {
                            const $t29584_i5511 = s.y;
                            return ($t29584_i5511 + 1.);
                          }
                        })();
                        {
                          const x_i12302 = (() => {
                            {
                              const $t29475_i12301 = (() => {
                                {
                                  const $t29474_i12300 = (() => {
                                    {
                                      const $t29472_i12298 = ($t29583_i5510 * 12.9898);
                                      {
                                        const $t29473_i12299 = ($t29585_i5512 * 78.233);
                                        return ($t29472_i12298 + $t29473_i12299);
                                      }
                                    }
                                  })();
                                  return Math.sin($t29474_i12300);
                                }
                              })();
                              return ($t29475_i12301 * 43758.5453);
                            }
                          })();
                          {
                            const $t29476_i12304 = (() => {
                              {
                                const $t1603_i5376_i12303 = Math.floor(x_i12302);
                                return $t1603_i5376_i12303;
                              }
                            })();
                            return (x_i12302 - $t29476_i12304);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t29586_i5514 = (r_i5513 < 0.34);
                    if ($t29586_i5514 === true) {
                      return 0;
                    } else {
                      return (() => {
                        {
                          const $t29587_i5515 = (r_i5513 < 0.67);
                          if ($t29587_i5515 === true) {
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
              if ($t29699 === 0) {
                return (() => {
                  {
                    const $jp_clo29702 = (() => {
                      return { $: "$Clo_$jp29701$3813", _0: $jp29701$apply$3813, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_ring(ctx, s, pulse);
                  }
                })();
              } else if ($t29699 === 1) {
                return (() => {
                  {
                    const $jp_clo29704 = (() => {
                      return { $: "$Clo_$jp29703$3814", _0: $jp29703$apply$3814, _1: ctx, _2: s, _3: t };
                    })();
                    return draw_pulse_halo(ctx, s, pulse);
                  }
                })();
              } else {
                return (() => {
                  {
                    const $t29700 = (() => {
                      {
                        const $t29606_i5507 = (() => {
                          {
                            const $t29605_i5506 = (() => {
                              {
                                const $t29604_i5505 = (() => {
                                  {
                                    const $t29601_i5502 = (() => {
                                      {
                                        const $t29600_i5501 = s.x;
                                        return ($t29600_i5501 + 4.);
                                      }
                                    })();
                                    {
                                      const $t29603_i5504 = (() => {
                                        {
                                          const $t29602_i5503 = s.y;
                                          return ($t29602_i5503 + 4.);
                                        }
                                      })();
                                      {
                                        const x_i12293 = (() => {
                                          {
                                            const $t29475_i12292 = (() => {
                                              {
                                                const $t29474_i12291 = (() => {
                                                  {
                                                    const $t29472_i12289 = ($t29601_i5502 * 12.9898);
                                                    {
                                                      const $t29473_i12290 = ($t29603_i5504 * 78.233);
                                                      return ($t29472_i12289 + $t29473_i12290);
                                                    }
                                                  }
                                                })();
                                                return Math.sin($t29474_i12291);
                                              }
                                            })();
                                            return ($t29475_i12292 * 43758.5453);
                                          }
                                        })();
                                        {
                                          const $t29476_i12295 = (() => {
                                            {
                                              const $t1603_i5376_i12294 = Math.floor(x_i12293);
                                              return $t1603_i5376_i12294;
                                            }
                                          })();
                                          return (x_i12293 - $t29476_i12295);
                                        }
                                      }
                                    }
                                  }
                                })();
                                return ($t29604_i5505 * 4.);
                              }
                            })();
                            return Math.trunc($t29605_i5506);
                          }
                        })();
                        return (2 + $t29606_i5507);
                      }
                    })();
                    return draw_pulse_particle(ctx, s, t, $t29700, 0);
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
      const $t29705 = star_targeted(s, aim);
      if ($t29705 === true) {
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
      const $t29706 = s.x;
      {
        const $t29707 = s.y;
        {
          const $t29708 = s.radius;
          return Canvas$arc(ctx, $t29706, $t29707, $t29708, 0., 6.28318530718);
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
            const $t29716 = (() => {
              {
                const $t29715 = (seed * 37.719);
                return (fx + $t29715);
              }
            })();
            {
              const $t29718 = (() => {
                {
                  const $t29717 = (seed * 12.9898);
                  return (fy - $t29717);
                }
              })();
              {
                const x_i5560 = (() => {
                  {
                    const $t29713_i5559 = (() => {
                      {
                        const $t29712_i5558 = (() => {
                          {
                            const $t29710_i5556 = ($t29716 * 12.9898);
                            {
                              const $t29711_i5557 = ($t29718 * 78.233);
                              return ($t29710_i5556 + $t29711_i5557);
                            }
                          }
                        })();
                        return Math.sin($t29712_i5558);
                      }
                    })();
                    return ($t29713_i5559 * 43758.5453);
                  }
                })();
                {
                  const $t29714_i5561 = (() => {
                    {
                      const $t1603_i12339 = Math.floor(x_i5560);
                      return $t1603_i12339;
                    }
                  })();
                  return (x_i5560 - $t29714_i5561);
                }
              }
            }
          }
        })();
        {
          const h2 = (() => {
            {
              const $t29721 = (() => {
                {
                  const $t29719 = (fy * 3.271);
                  {
                    const $t29720 = (seed * 71.238);
                    return ($t29719 - $t29720);
                  }
                }
              })();
              {
                const $t29724 = (() => {
                  {
                    const $t29722 = (fx * 1.373);
                    {
                      const $t29723 = (seed * 5.113);
                      return ($t29722 + $t29723);
                    }
                  }
                })();
                {
                  const x_i5552 = (() => {
                    {
                      const $t29713_i5551 = (() => {
                        {
                          const $t29712_i5550 = (() => {
                            {
                              const $t29710_i5548 = ($t29721 * 12.9898);
                              {
                                const $t29711_i5549 = ($t29724 * 78.233);
                                return ($t29710_i5548 + $t29711_i5549);
                              }
                            }
                          })();
                          return Math.sin($t29712_i5550);
                        }
                      })();
                      return ($t29713_i5551 * 43758.5453);
                    }
                  })();
                  {
                    const $t29714_i5553 = (() => {
                      {
                        const $t1603_i12336 = Math.floor(x_i5552);
                        return $t1603_i12336;
                      }
                    })();
                    return (x_i5552 - $t29714_i5553);
                  }
                }
              }
            }
          })();
          {
            const $t29727 = (() => {
              {
                const $t29725 = (h1 * 269.5);
                {
                  const $t29726 = (h2 * 183.3);
                  return ($t29725 + $t29726);
                }
              }
            })();
            {
              const $t29731 = (() => {
                {
                  const $t29730 = (() => {
                    {
                      const $t29728 = (fx * 0.618);
                      {
                        const $t29729 = (fy * 0.573);
                        return ($t29728 + $t29729);
                      }
                    }
                  })();
                  return ($t29730 + seed);
                }
              })();
              {
                const x_i5544 = (() => {
                  {
                    const $t29713_i5543 = (() => {
                      {
                        const $t29712_i5542 = (() => {
                          {
                            const $t29710_i5540 = ($t29727 * 12.9898);
                            {
                              const $t29711_i5541 = ($t29731 * 78.233);
                              return ($t29710_i5540 + $t29711_i5541);
                            }
                          }
                        })();
                        return Math.sin($t29712_i5542);
                      }
                    })();
                    return ($t29713_i5543 * 43758.5453);
                  }
                })();
                {
                  const $t29714_i5545 = (() => {
                    {
                      const $t1603_i12333 = Math.floor(x_i5544);
                      return $t1603_i12333;
                    }
                  })();
                  return (x_i5544 - $t29714_i5545);
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
      const $t29733 = (h > 0.5);
      if ($t29733 === true) {
        return {  };
      } else {
        return (() => {
          {
            const jx = (() => {
              {
                const $t29734 = (gy + 1000);
                return bg_hash(gx, $t29734, seed);
              }
            })();
            {
              const jy = (() => {
                {
                  const $t29735 = (gx + 1000);
                  return bg_hash($t29735, gy, seed);
                }
              })();
              {
                const x = (() => {
                  {
                    const $t29737 = (() => {
                      {
                        const $t29736 = gx;
                        return ($t29736 * cell);
                      }
                    })();
                    {
                      const $t29738 = (jx * cell);
                      return ($t29737 + $t29738);
                    }
                  }
                })();
                {
                  const y = (() => {
                    {
                      const $t29740 = (() => {
                        {
                          const $t29739 = gy;
                          return ($t29739 * cell);
                        }
                      })();
                      {
                        const $t29741 = (jy * cell);
                        return ($t29740 + $t29741);
                      }
                    }
                  })();
                  {
                    const br = (() => {
                      {
                        const $t29745 = (() => {
                          {
                            const $t29744 = (() => {
                              {
                                const $t29742 = (gx + 2000);
                                {
                                  const $t29743 = (gy + 2000);
                                  return bg_hash($t29742, $t29743, seed);
                                }
                              }
                            })();
                            return (0.45 * $t29744);
                          }
                        })();
                        return (0.12 + $t29745);
                      }
                    })();
                    {
                      const st = (() => {
                        {
                          const $t29746 = (gx - 2000);
                          {
                            const $t29747 = (gy - 2000);
                            return bg_hash($t29746, $t29747, seed);
                          }
                        }
                      })();
                      {
                        const sz = (() => {
                          {
                            const $t29749 = (() => {
                              {
                                const $t29748 = (1.8 * st);
                                return ($t29748 * st);
                              }
                            })();
                            return (1. + $t29749);
                          }
                        })();
                        {
                          const is_pulsing = (() => {
                            {
                              const $t29752 = (() => {
                                {
                                  const $t29750 = (gx + 3000);
                                  {
                                    const $t29751 = (gy + 3000);
                                    return bg_hash($t29750, $t29751, seed);
                                  }
                                }
                              })();
                              return ($t29752 < 0.04);
                            }
                          })();
                          {
                            let pulse;
                            if (is_pulsing === true) {
                              pulse = (() => {
                                {
                                  const speed = (() => {
                                    {
                                      const $t29756 = (() => {
                                        {
                                          const $t29755 = (() => {
                                            {
                                              const $t29754 = (gx + 4000);
                                              return bg_hash($t29754, gy, seed);
                                            }
                                          })();
                                          return (0.45 * $t29755);
                                        }
                                      })();
                                      return (0.35 + $t29756);
                                    }
                                  })();
                                  {
                                    const phase = (() => {
                                      {
                                        const $t29758 = (() => {
                                          {
                                            const $t29757 = (gy + 4000);
                                            return bg_hash(gx, $t29757, seed);
                                          }
                                        })();
                                        return ($t29758 * 6.28318530718);
                                      }
                                    })();
                                    {
                                      const $t29763 = (() => {
                                        {
                                          const $t29762 = (() => {
                                            {
                                              const $t29761 = (() => {
                                                {
                                                  const $t29760 = (t * speed);
                                                  return ($t29760 + phase);
                                                }
                                              })();
                                              return Math.sin($t29761);
                                            }
                                          })();
                                          return (0.5 * $t29762);
                                        }
                                      })();
                                      return (0.5 + $t29763);
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
                                    const $t29766 = (() => {
                                      {
                                        const $t29765 = (() => {
                                          {
                                            const $t29764 = (1. - br);
                                            return ($t29764 * 0.6);
                                          }
                                        })();
                                        return ($t29765 * pulse);
                                      }
                                    })();
                                    return (br + $t29766);
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
                                      const $t29768 = (() => {
                                        {
                                          const $t29767 = (0.35 * pulse);
                                          return (1. + $t29767);
                                        }
                                      })();
                                      return (sz * $t29768);
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
    const $t29770 = (gx > gx_max);
    if ($t29770 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_cell(ctx, gx, gy, cell, seed, t);
        })();
        {
          const $t29771 = (gx + 1);
          return draw_bg_row(ctx, $t29771, gx_max, gy, cell, seed, t);
        }
      })();
    }
  }
}
const draw_bg_row$clo = { _0: ($_, ctx, gx, gx_max, gy, cell, seed, t) => draw_bg_row(ctx, gx, gx_max, gy, cell, seed, t) };

function draw_bg_rows(ctx, gx0, gx1, gy, gy_max, cell, seed, t) {
  {
    const $t29772 = (gy > gy_max);
    if ($t29772 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          return draw_bg_row(ctx, gx0, gx1, gy, cell, seed, t);
        })();
        {
          const $t29773 = (gy + 1);
          return draw_bg_rows(ctx, gx0, gx1, $t29773, gy_max, cell, seed, t);
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
        const $t29776 = (() => {
          {
            const $t29775 = (() => {
              {
                const $t29774 = (cam_x / 70.);
                {
                  const $t1603_i5570 = Math.floor($t29774);
                  return $t1603_i5570;
                }
              }
            })();
            return Math.trunc($t29775);
          }
        })();
        return ($t29776 - 1);
      }
    })();
    {
      const gx1 = (() => {
        {
          const $t29780 = (() => {
            {
              const $t29779 = (() => {
                {
                  const $t29778 = (() => {
                    {
                      const $t29777 = (cam_x + view_w);
                      return ($t29777 / 70.);
                    }
                  })();
                  {
                    const $t1603_i5568 = Math.floor($t29778);
                    return $t1603_i5568;
                  }
                }
              })();
              return Math.trunc($t29779);
            }
          })();
          return ($t29780 + 1);
        }
      })();
      {
        const gy0 = (() => {
          {
            const $t29783 = (() => {
              {
                const $t29782 = (() => {
                  {
                    const $t29781 = (cam / 70.);
                    {
                      const $t1603_i5566 = Math.floor($t29781);
                      return $t1603_i5566;
                    }
                  }
                })();
                return Math.trunc($t29782);
              }
            })();
            return ($t29783 - 1);
          }
        })();
        {
          const gy1 = (() => {
            {
              const $t29787 = (() => {
                {
                  const $t29786 = (() => {
                    {
                      const $t29785 = (() => {
                        {
                          const $t29784 = (cam + view_h);
                          return ($t29784 / 70.);
                        }
                      })();
                      {
                        const $t1603_i5564 = Math.floor($t29785);
                        return $t1603_i5564;
                      }
                    }
                  })();
                  return Math.trunc($t29786);
                }
              })();
              return ($t29787 + 1);
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
      const $f29794 = clouds._0;
      const $f29795 = clouds._1;
      {
        const rest = (() => {
          return $f29795;
        })();
        {
          const c = (() => {
            return $f29794;
          })();
          (() => {
            {
              const $t29788 = c.x;
              {
                const $t29789 = c.y;
                {
                  const $t29790 = c.radius;
                  {
                    const $t29793 = (() => {
                      {
                        const $t29792 = c.strength;
                        return (0.16 * $t29792);
                      }
                    })();
                    return Canvas$fill_noise_circle(ctx, $t29788, $t29789, $t29790, $t29793);
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
    const $t29800 = (() => {
      {
        const margin_i5578 = (700. + 90.);
        {
          const $t29404_i5579 = { $: "Nil" };
          {
            const $t29405_i5580 = Perihelion$Nebula$filter_visible(stars, cam, view_h, margin_i5578, $t29404_i5579);
            {
              const $t29406_i5581 = { $: "Nil" };
              return Perihelion$Nebula$collect_star_clouds($t29405_i5580, seed, $t29406_i5581);
            }
          }
        }
      }
    })();
    {
      const $rc_627 = draw_nebula_clouds(ctx, $t29800);
      return $rc_627;
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
      const $f29809 = stars._0;
      const $f29810 = stars._1;
      {
        const rest = $f29810;
        {
          const s = $f29809;
          (() => {
            {
              const $t29808 = (() => {
                {
                  const $t29804 = (() => {
                    {
                      const $t29801 = s.y;
                      {
                        const $t29803 = (() => {
                          {
                            const $t29802 = (cam + view_h);
                            return ($t29802 + 100.);
                          }
                        })();
                        return ($t29801 < $t29803);
                      }
                    }
                  })();
                  {
                    const $t29807 = (() => {
                      {
                        const $t29805 = s.y;
                        {
                          const $t29806 = (cam - 100.);
                          return ($t29805 > $t29806);
                        }
                      }
                    })();
                    return ($t29804 && $t29807);
                  }
                }
              })();
              if ($t29808 === true) {
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
        const $t29821 = i;
        {
          const $t29823 = (6.28318530718 / 8.);
          return ($t29821 * $t29823);
        }
      }
    })();
    {
      const jitter = (() => {
        {
          const $t29826 = (() => {
            {
              const $t29825 = (() => {
                {
                  const $t29824 = a.shape_seed;
                  {
                    const x_i5595 = (() => {
                      {
                        const $t29819_i5594 = (() => {
                          {
                            const $t29818_i5593 = (() => {
                              {
                                const $t29815_i5590 = ($t29824 * 12.9898);
                                {
                                  const $t29817_i5592 = (() => {
                                    {
                                      const $t29816_i5591 = i;
                                      return ($t29816_i5591 * 78.233);
                                    }
                                  })();
                                  return ($t29815_i5590 + $t29817_i5592);
                                }
                              }
                            })();
                            return Math.sin($t29818_i5593);
                          }
                        })();
                        return ($t29819_i5594 * 43758.5453);
                      }
                    })();
                    {
                      const $t29820_i5596 = (() => {
                        {
                          const $t1603_i12342 = Math.floor(x_i5595);
                          return $t1603_i12342;
                        }
                      })();
                      return (x_i5595 - $t29820_i5596);
                    }
                  }
                }
              })();
              return (0.6 * $t29825);
            }
          })();
          return (0.7 + $t29826);
        }
      })();
      {
        const r = (() => {
          {
            const $t29827 = a.radius;
            return ($t29827 * jitter);
          }
        })();
        {
          const pt = (() => {
            {
              const $t29831 = (() => {
                {
                  const $t29828 = a.x;
                  {
                    const $t29830 = (() => {
                      {
                        const $t29829 = Math.cos(angle);
                        return ($t29829 * r);
                      }
                    })();
                    return ($t29828 + $t29830);
                  }
                }
              })();
              {
                const $t29835 = (() => {
                  {
                    const $t29832 = a.y;
                    {
                      const $t29834 = (() => {
                        {
                          const $t29833 = Math.sin(angle);
                          return ($t29833 * r);
                        }
                      })();
                      return ($t29832 + $t29834);
                    }
                  }
                })();
                return { _0: $t29831, _1: $t29835 };
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
    const $t29836 = (i > 7);
    if ($t29836 === true) {
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
                      const $jp_clo29838 = (() => {
                        return { $: "$Clo_$jp29837$3817", _0: $jp29837$apply$3817, _1: ctx, _2: px, _3: py };
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
                const $t29839 = (i + 1);
                return draw_asteroid_edges(ctx, a, $t29839);
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
      const $f29848 = asteroids._0;
      const $f29849 = asteroids._1;
      {
        const rest = (() => {
          return $f29849;
        })();
        {
          const a = (() => {
            return $f29848;
          })();
          {
            const color = (() => {
              {
                const $t29841 = a.mode;
                switch ($t29841.$) {
                  case "AsteroidDrifting": {
                    return "#8a8a94";
                    break;
                  }
                  case "AsteroidOrbiting": {
                    const $f29842 = $t29841._0;
                    const $f29843 = $t29841._1;
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
      const $f29857 = shots._0;
      const $f29858 = shots._1;
      {
        const rest = (() => {
          return $f29858;
        })();
        {
          const s = (() => {
            return $f29857;
          })();
          (() => {
            return Canvas$set_fill_style(ctx, color);
          })();
          (() => {
            return Canvas$begin_path(ctx);
          })();
          (() => {
            {
              const $t29854 = s.x;
              {
                const $t29855 = s.y;
                return Canvas$arc(ctx, $t29854, $t29855, r, 0., 6.28318530718);
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
    const $t29863 = sh.mode;
    switch ($t29863.$) {
      case "ShipOrbiting": {
        const $f29867 = $t29863._0;
        {
          const angle = (() => {
            return $f29867;
          })();
          {
            const d = (0. - 1.);
            {
              const $t29866 = (d * 1.5707963);
              return (angle + $t29866);
            }
          }
        }
        break;
      }
      case "ShipFlying": {
        const $f29868 = $t29863._0;
        const $f29869 = $t29863._1;
        {
          const vy = (() => {
            return $f29869;
          })();
          {
            const vx = (() => {
              return $f29868;
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
      const $f29878 = ships._0;
      const $f29879 = ships._1;
      {
        const rest = (() => {
          return $f29879;
        })();
        {
          const sh = (() => {
            return $f29878;
          })();
          {
            const pos = (() => {
              {
                const pos_i5608 = (() => {
                  {
                    const $t27598_i5606 = sh.x;
                    {
                      const $t27599_i5607 = sh.y;
                      return { _0: $t27598_i5606, _1: $t27599_i5607 };
                    }
                  }
                })();
                return pos_i5608;
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
                      const $t29874 = (0. - 6.);
                      return Canvas$line_to(ctx, $t29874, 5.);
                    }
                  })();
                  (() => {
                    {
                      const $t29875 = (0. - 6.);
                      {
                        const $t29876 = (0. - 5.);
                        return Canvas$line_to(ctx, $t29875, $t29876);
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
      const $f29887 = pickups._0;
      const $f29888 = pickups._1;
      {
        const rest = (() => {
          return $f29888;
        })();
        {
          const pk = (() => {
            return $f29887;
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
              const $t29884 = pk.x;
              {
                const $t29885 = pk.y;
                return Canvas$arc(ctx, $t29884, $t29885, 8., 0., 6.28318530718);
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
    const $t29893 = (i >= 5);
    if ($t29893 === true) {
      return {  };
    } else {
      return (() => {
        switch (runs.$) {
          case "Nil": {
            return {  };
            break;
          }
          case "Cons": {
            const $f29906 = runs._0;
            const $f29907 = runs._1;
            {
              const rest = (() => {
                return $f29907;
              })();
              {
                const r = (() => {
                  return $f29906;
                })();
                (() => {
                  return Canvas$set_font(ctx, "14px sans-serif");
                })();
                (() => {
                  {
                    const $t29902 = (() => {
                      {
                        const $t29901 = (() => {
                          {
                            const $t29898 = (() => {
                              {
                                const $t29895 = (() => {
                                  {
                                    const $t29894 = r.score;
                                    return String($t29894);
                                  }
                                })();
                                {
                                  const $t29897 = (() => {
                                    {
                                      const $t29896 = r.max_mult;
                                      return String($t29896);
                                    }
                                  })();
                                  {
                                    const $rc_630 = march_string_concat3($t29895, " x", $t29897);
                                    return $rc_630;
                                  }
                                }
                              }
                            })();
                            {
                              const $t29900 = (() => {
                                {
                                  const $t29899 = r.stars;
                                  return String($t29899);
                                }
                              })();
                              {
                                const $rc_629 = march_string_concat3($t29898, " · ", $t29900);
                                return $rc_629;
                              }
                            }
                          }
                        })();
                        {
                          const $rc_628 = ($t29901 + " stars");
                          return $rc_628;
                        }
                      }
                    })();
                    {
                      const $t29903 = (view_w / 2.);
                      return Canvas$fill_text(ctx, $t29902, $t29903, y);
                    }
                  }
                })();
                {
                  const $t29904 = (y + 20.);
                  {
                    const $t29905 = (i + 1);
                    return draw_runs(ctx, rest, view_w, $t29904, $t29905);
                  }
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
      const $t29912 = game.ball_x;
      {
        const $t29913 = game.ball_y;
        return Canvas$arc(ctx, $t29912, $t29913, 6., 0., 6.28318530718);
      }
    }
  })();
  (() => {
    return Canvas$fill(ctx);
  })();
  {
    const $t29916 = (() => {
      {
        const $t29915 = game.shield;
        return ($t29915 > 0);
      }
    })();
    if ($t29916 === true) {
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
            const $t29917 = game.ball_x;
            {
              const $t29918 = game.ball_y;
              return Canvas$arc(ctx, $t29917, $t29918, 10., 0., 6.28318530718);
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
      const $t29922 = (cx - 60.);
      {
        const $t29924 = (() => {
          {
            const $t29923 = (view_h / 2.);
            return ($t29923 - 60.);
          }
        })();
        return Canvas$stroke_rect(ctx, $t29922, $t29924, 120., 120.);
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
    let $t29925;
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29920_i5615 = u._0;
        $t29925 = (() => {
          switch ($f29920_i5615.$) {
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
        $t29925 = "Faster Fire";
        break;
      }
      case "DefenseBulletWard": {
        $t29925 = "Bullet Ward";
        break;
      }
      case "DefenseDeflector": {
        $t29925 = "Deflector Plating";
        break;
      }
      case "DefenseShield": {
        $t29925 = "Reinforced Shield";
        break;
      }
      case "SpecialItem": {
        const $f29921_i5616 = u._0;
        $t29925 = (() => {
          switch ($f29921_i5616.$) {
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
        $t29925 = (() => { throw new Error("non-exhaustive pattern match"); })();
        break;
      }
    }
    {
      const $t29926 = (view_h / 2.);
      return Canvas$fill_text(ctx, $t29925, cx, $t29926);
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
      const $f29931 = choices._0;
      const $f29932 = choices._1;
      {
        const rest = (() => {
          return $f29932;
        })();
        {
          const u = (() => {
            return $f29931;
          })();
          {
            const col_w = (view_w / 3.);
            (() => {
              {
                const $t29929 = (() => {
                  {
                    const $t29928 = (() => {
                      {
                        const $t29927 = i;
                        return ($t29927 + 0.5);
                      }
                    })();
                    return (col_w * $t29928);
                  }
                })();
                {
                  const $rc_631 = (() => {
                    return draw_milestone_card(ctx, u, $t29929, view_h);
                  })();
                  return $rc_631;
                }
              }
            })();
            {
              const $t29930 = (i + 1);
              return draw_milestone_cards(ctx, rest, view_w, view_h, $t29930);
            }
          }
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
      const $t29938 = (() => {
        {
          const $t29937 = game.score;
          return String($t29937);
        }
      })();
      return Canvas$fill_text(ctx, $t29938, 14., 28.);
    }
  })();
  (() => {
    return Canvas$set_text_align(ctx, "right");
  })();
  (() => {
    {
      const $t29941 = (() => {
        {
          const $t29940 = (() => {
            {
              const $t29939 = game.best;
              return String($t29939);
            }
          })();
          {
            const $rc_639 = ("best " + $t29940);
            return $rc_639;
          }
        }
      })();
      {
        const $t29943 = (() => {
          {
            const $t29942 = game.view_w;
            return ($t29942 - 14.);
          }
        })();
        return Canvas$fill_text(ctx, $t29941, $t29943, 28.);
      }
    }
  })();
  (() => {
    {
      const $t29945 = (() => {
        {
          const $t29944 = game.multiplier;
          return ($t29944 > 1);
        }
      })();
      if ($t29945 === true) {
        return (() => {
          (() => {
            return Canvas$set_text_align(ctx, "left");
          })();
          {
            const $t29948 = (() => {
              {
                const $t29947 = (() => {
                  {
                    const $t29946 = game.multiplier;
                    return String($t29946);
                  }
                })();
                {
                  const $rc_638 = ("x" + $t29947);
                  return $rc_638;
                }
              }
            })();
            return Canvas$fill_text(ctx, $t29948, 14., 52.);
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
      const $t29951 = (() => {
        {
          const $t29950 = (() => {
            {
              const $t29949 = Perihelion$Core$active_weapon(game);
              return { $: "OffenseWeapon", _0: $t29949 };
            }
          })();
          {
            let $rc_637;
            switch ($t29950.$) {
              case "OffenseWeapon": {
                const $f29920_i5624 = $t29950._0;
                $rc_637 = (() => {
                  switch ($f29920_i5624.$) {
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
                $rc_637 = "Faster Fire";
                break;
              }
              case "DefenseBulletWard": {
                $rc_637 = "Bullet Ward";
                break;
              }
              case "DefenseDeflector": {
                $rc_637 = "Deflector Plating";
                break;
              }
              case "DefenseShield": {
                $rc_637 = "Reinforced Shield";
                break;
              }
              case "SpecialItem": {
                const $f29921_i5625 = $t29950._0;
                $rc_637 = (() => {
                  switch ($f29921_i5625.$) {
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
                $rc_637 = (() => { throw new Error("non-exhaustive pattern match"); })();
                break;
              }
            }
            return $rc_637;
          }
        }
      })();
      {
        const $t29953 = (() => {
          {
            const $t29952 = game.view_h;
            return ($t29952 - 60.);
          }
        })();
        return Canvas$fill_text(ctx, $t29951, 14., $t29953);
      }
    }
  })();
  (() => {
    {
      const $t29954 = game.special;
      switch ($t29954.$) {
        case "None": {
          return {  };
          break;
        }
        case "Some": {
          const $f29962 = $t29954._0;
          {
            const k = (() => {
              return $f29962;
            })();
            {
              const $t29959 = (() => {
                {
                  const $t29956 = (() => {
                    {
                      const $t29955 = { $: "SpecialItem", _0: k };
                      {
                        let $rc_636;
                        switch ($t29955.$) {
                          case "OffenseWeapon": {
                            const $f29920_i5621 = $t29955._0;
                            $rc_636 = (() => {
                              switch ($f29920_i5621.$) {
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
                            $rc_636 = "Faster Fire";
                            break;
                          }
                          case "DefenseBulletWard": {
                            $rc_636 = "Bullet Ward";
                            break;
                          }
                          case "DefenseDeflector": {
                            $rc_636 = "Deflector Plating";
                            break;
                          }
                          case "DefenseShield": {
                            $rc_636 = "Reinforced Shield";
                            break;
                          }
                          case "SpecialItem": {
                            const $f29921_i5622 = $t29955._0;
                            $rc_636 = (() => {
                              switch ($f29921_i5622.$) {
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
                            $rc_636 = (() => { throw new Error("non-exhaustive pattern match"); })();
                            break;
                          }
                        }
                        return $rc_636;
                      }
                    }
                  })();
                  {
                    const $t29958 = (() => {
                      {
                        const $t29957 = game.special_charges;
                        return String($t29957);
                      }
                    })();
                    {
                      const $rc_635 = march_string_concat3($t29956, " x", $t29958);
                      return $rc_635;
                    }
                  }
                }
              })();
              {
                const $t29961 = (() => {
                  {
                    const $t29960 = game.view_h;
                    return ($t29960 - 40.);
                  }
                })();
                return Canvas$fill_text(ctx, $t29959, 14., $t29961);
              }
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
        const $t29964 = (() => {
          {
            const $t29963 = game.bullet_ward;
            if ($t29963 === true) {
              return "ward ";
            } else {
              return "";
            }
          }
        })();
        {
          const $t29966 = (() => {
            {
              const $t29965 = game.deflector_plating;
              if ($t29965 === true) {
                return "deflect ";
              } else {
                return "";
              }
            }
          })();
          {
            const $t29971 = (() => {
              {
                const $t29968 = (() => {
                  {
                    const $t29967 = game.shield;
                    return ($t29967 > 0);
                  }
                })();
                if ($t29968 === true) {
                  return (() => {
                    {
                      const $t29970 = (() => {
                        {
                          const $t29969 = game.shield;
                          return String($t29969);
                        }
                      })();
                      {
                        const $rc_634 = ("shield x" + $t29970);
                        return $rc_634;
                      }
                    }
                  })();
                } else {
                  return "";
                }
              }
            })();
            {
              const $rc_633 = march_string_concat3($t29964, $t29966, $t29971);
              return $rc_633;
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t29973 = (() => {
          {
            const $t29972 = game.view_h;
            return ($t29972 - 20.);
          }
        })();
        return Canvas$fill_text(ctx, defense_tags, 14., $t29973);
      }
    })();
    (() => {
      return Canvas$set_text_align(ctx, "center");
    })();
    {
      const $t29974 = game.phase;
      switch ($t29974.$) {
        case "Ready": {
          (() => {
            return Canvas$set_font(ctx, "22px sans-serif");
          })();
          {
            const $t29976 = (() => {
              {
                const $t29975 = game.view_w;
                return ($t29975 / 2.);
              }
            })();
            {
              const $t29978 = (() => {
                {
                  const $t29977 = game.view_h;
                  return ($t29977 / 2.);
                }
              })();
              return Canvas$fill_text(ctx, "tap to start", $t29976, $t29978);
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
              const $t29981 = (() => {
                {
                  const $t29980 = (() => {
                    {
                      const $t29979 = game.score;
                      return String($t29979);
                    }
                  })();
                  {
                    const $rc_632 = march_string_concat3("score ", $t29980, " — tap to retry");
                    return $rc_632;
                  }
                }
              })();
              {
                const $t29983 = (() => {
                  {
                    const $t29982 = game.view_w;
                    return ($t29982 / 2.);
                  }
                })();
                {
                  const $t29985 = (() => {
                    {
                      const $t29984 = game.view_h;
                      return ($t29984 / 2.);
                    }
                  })();
                  return Canvas$fill_text(ctx, $t29981, $t29983, $t29985);
                }
              }
            }
          })();
          {
            const $t29986 = game.runs;
            {
              const $t29987 = game.view_w;
              {
                const $t29990 = (() => {
                  {
                    const $t29989 = (() => {
                      {
                        const $t29988 = game.view_h;
                        return ($t29988 / 2.);
                      }
                    })();
                    return ($t29989 + 36.);
                  }
                })();
                return draw_runs(ctx, $t29986, $t29987, $t29990, 0);
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
              const $t29992 = (() => {
                {
                  const $t29991 = game.view_w;
                  return ($t29991 / 2.);
                }
              })();
              {
                const $t29995 = (() => {
                  {
                    const $t29994 = (() => {
                      {
                        const $t29993 = game.view_h;
                        return ($t29993 / 2.);
                      }
                    })();
                    return ($t29994 - 90.);
                  }
                })();
                return Canvas$fill_text(ctx, "Choose an upgrade", $t29992, $t29995);
              }
            }
          })();
          {
            const $t29996 = game.milestone_choices;
            {
              const $t29997 = game.view_w;
              {
                const $t29998 = game.view_h;
                return draw_milestone_cards(ctx, $t29996, $t29997, $t29998, 0);
              }
            }
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
      const $t29999 = game.view_w;
      {
        const $t30000 = game.view_h;
        return Canvas$fill_rect(ctx, 0., 0., $t29999, $t30000);
      }
    }
  })();
  (() => {
    return Canvas$save(ctx);
  })();
  (() => {
    {
      const $t30002 = (() => {
        {
          const $t30001 = game.camera_x;
          return (0. - $t30001);
        }
      })();
      {
        const $t30004 = (() => {
          {
            const $t30003 = game.camera_y;
            return (0. - $t30003);
          }
        })();
        return Canvas$translate(ctx, $t30002, $t30004);
      }
    }
  })();
  {
    const seedf = (() => {
      {
        const $t30005 = game.seed;
        return $t30005;
      }
    })();
    (() => {
      {
        const $t30006 = game.camera_x;
        {
          const $t30007 = game.camera_y;
          {
            const $t30008 = game.view_w;
            {
              const $t30009 = game.view_h;
              {
                const $t30010 = fx.t;
                return draw_starfield(ctx, $t30006, $t30007, $t30008, $t30009, seedf, $t30010);
              }
            }
          }
        }
      }
    })();
    (() => {
      {
        const $t30011 = game.stars;
        {
          const $t30012 = game.camera_y;
          {
            const $t30013 = game.view_h;
            return draw_nebula(ctx, $t30011, $t30012, $t30013, seedf);
          }
        }
      }
    })();
    {
      const aim = (() => {
        {
          const $t30014 = game.mode;
          switch ($t30014.$) {
            case "Flying": {
              const $f30018 = $t30014._0;
              const $f30019 = $t30014._1;
              {
                const vy = (() => {
                  return $f30019;
                })();
                {
                  const vx = (() => {
                    return $f30018;
                  })();
                  {
                    const $t30015 = game.ball_x;
                    {
                      const $t30016 = game.ball_y;
                      {
                        const $t30017 = { _0: $t30015, _1: $t30016, _2: vx, _3: vy };
                        return { $: "Some", _0: $t30017 };
                      }
                    }
                  }
                }
              }
              break;
            }
            case "Orbiting": {
              const $f30024 = $t30014._0;
              const $f30025 = $t30014._1;
              const $f30026 = $t30014._2;
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
          const $t30035 = game.stars;
          {
            const $t30036 = game.camera_y;
            {
              const $t30037 = game.view_h;
              {
                const $t30038 = fx.t;
                {
                  const $rc_641 = (() => {
                    return draw_stars(ctx, $t30035, $t30036, $t30037, $t30038, aim);
                  })();
                  return $rc_641;
                }
              }
            }
          }
        }
      })();
      (() => {
        {
          const $t30039 = Perihelion$Core$active_weapon(game);
          switch ($t30039.$) {
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
          const $t30042 = game.mode;
          switch ($t30042.$) {
            case "Orbiting": {
              const $f30050 = $t30042._0;
              const $f30051 = $t30042._1;
              const $f30052 = $t30042._2;
              {
                const angle = (() => {
                  return $f30052;
                })();
                {
                  const ring = (() => {
                    return $f30051;
                  })();
                  {
                    const idx = (() => {
                      return $f30050;
                    })();
                    {
                      const $t30043 = game.special;
                      switch ($t30043.$) {
                        case "Some": {
                          const $f30045 = $t30043._0;
                          switch ($f30045.$) {
                            case "TrajectoryPreview": {
                              {
                                const $t30044 = Perihelion$Core$predict_trajectory(game, idx, ring, angle);
                                {
                                  const $rc_640 = (() => {
                                    return draw_trajectory_preview(ctx, $t30044);
                                  })();
                                  return $rc_640;
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
              const $f30061 = $t30042._0;
              const $f30062 = $t30042._1;
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
          const $t30067 = fx.flash;
          return draw_flash(ctx, $t30067);
        }
      })();
      (() => {
        {
          const $t30068 = game.asteroids;
          return draw_asteroids(ctx, $t30068);
        }
      })();
      (() => {
        {
          const $t30069 = game.ships;
          return draw_ships(ctx, $t30069);
        }
      })();
      (() => {
        {
          const $t30070 = game.player_shots;
          return draw_shots(ctx, $t30070, "#ffffff", 3.);
        }
      })();
      (() => {
        {
          const $t30071 = game.enemy_shots;
          return draw_shots(ctx, $t30071, "#8a8a94", 2.5);
        }
      })();
      (() => {
        {
          const $t30072 = game.pickups;
          return draw_pickups(ctx, $t30072);
        }
      })();
      (() => {
        {
          const $t30073 = fx.trail;
          return draw_trail(ctx, $t30073, 0, 14);
        }
      })();
      (() => {
        {
          const $t30075 = fx.particles;
          return draw_particles(ctx, $t30075);
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
    const $t30077 = (() => {
      {
        const $t30076 = Perihelion$Combat$starkiller_target_idx(game);
        return Perihelion$Core$star_at(game, $t30076);
      }
    })();
    switch ($t30077.$) {
      case "None": {
        return {  };
        break;
      }
      case "Some": {
        const $f30083 = $t30077._0;
        {
          const s = $f30083;
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
              const $t30078 = s.x;
              {
                const $t30079 = s.y;
                {
                  const $t30081 = (() => {
                    {
                      const $t30080 = s.capture_radius;
                      return ($t30080 + 12.);
                    }
                  })();
                  return Canvas$arc(ctx, $t30078, $t30079, $t30081, 0., 6.28318530718);
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
      const $f30089 = points._0;
      const $f30090 = points._1;
      {
        const rest = (() => {
          return $f30090;
        })();
        {
          const pt = (() => {
            return $f30089;
          })();
          {
            const x = pt._0;
            {
              const y = pt._1;
              (() => {
                {
                  const $t30085 = (() => {
                    {
                      const $t30084 = march_int_mod(i, 3);
                      return ($t30084 === 0);
                    }
                  })();
                  if ($t30085 === true) {
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
                const $t30087 = (i + 1);
                return draw_trajectory_dots(ctx, rest, $t30087);
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
    const $t30101 = (() => {
      {
        const $t30098 = (() => {
          {
            const $t30097 = game.view_w;
            return (w === $t30097);
          }
        })();
        {
          const $t30100 = (() => {
            {
              const $t30099 = game.view_h;
              return (h === $t30099);
            }
          })();
          return ($t30098 && $t30100);
        }
      }
    })();
    if ($t30101 === true) {
      return {  };
    } else {
      return (() => {
        (() => {
          {
            const $t30103 = (() => {
              {
                const $t30102 = Math.trunc(w);
                return String($t30102);
              }
            })();
            return Dom$set_attr(el, "width", $t30103);
          }
        })();
        {
          const $t30105 = (() => {
            {
              const $t30104 = Math.trunc(h);
              return String($t30104);
            }
          })();
          return Dom$set_attr(el, "height", $t30105);
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
          const $t30119 = (() => {
            {
              const $t30117 = (() => {
                {
                  const $t30116 = game.phase;
                  switch ($t30116.$) {
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
                const $t30118 = (() => {
                  {
                    const $t30095_i5657 = g2.phase;
                    switch ($t30095_i5657.$) {
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
                return ($t30117 && $t30118);
              }
            }
          })();
          if ($t30119 === true) {
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
          const $t30124 = (() => {
            {
              const $t30121 = (() => {
                {
                  const $t30120 = game.mode;
                  switch ($t30120.$) {
                    case "Orbiting": {
                      const $f30106_i5653 = $t30120._0;
                      const $f30107_i5654 = $t30120._1;
                      const $f30108_i5655 = $t30120._2;
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
                const $t30123 = (() => {
                  {
                    const $t30122 = g2.mode;
                    switch ($t30122.$) {
                      case "Flying": {
                        const $f30109_i5650 = $t30122._0;
                        const $f30110_i5651 = $t30122._1;
                        return true;
                        break;
                      }
                      default: {
                        return false;
                      }
                    }
                  }
                })();
                return ($t30121 && $t30123);
              }
            }
          })();
          if ($t30124 === true) {
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
          const $t30125 = g2.capture_flash;
          switch ($t30125.$) {
            case "None": {
              return {  };
              break;
            }
            case "Some": {
              const $f30126 = $t30125._0;
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
          const $t30131 = (() => {
            {
              const $t30128 = (() => {
                {
                  const $t30127 = g2.player_shots;
                  {
                    const go_i5647 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                    return go$apply$4823(go_i5647, $t30127, 0);
                  }
                }
              })();
              {
                const $t30130 = (() => {
                  {
                    const $t30129 = game.player_shots;
                    {
                      const go_i5645 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                      return go$apply$4823(go_i5645, $t30129, 0);
                    }
                  }
                })();
                return ($t30128 > $t30130);
              }
            }
          })();
          if ($t30131 === true) {
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
          const $t30136 = (() => {
            {
              const $t30133 = (() => {
                {
                  const $t30132 = g2.enemy_shots;
                  {
                    const go_i5643 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                    return go$apply$4823(go_i5643, $t30132, 0);
                  }
                }
              })();
              {
                const $t30135 = (() => {
                  {
                    const $t30134 = game.enemy_shots;
                    {
                      const go_i5641 = { $: "$Clo_go$4823", _0: go$apply$4823 };
                      return go$apply$4823(go_i5641, $t30134, 0);
                    }
                  }
                })();
                return ($t30133 > $t30135);
              }
            }
          })();
          if ($t30136 === true) {
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
          const $t30139 = (() => {
            {
              const $t30138 = (() => {
                {
                  const $t30137 = g2.fx_bursts;
                  switch ($t30137.$) {
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
              return (!$t30138);
            }
          })();
          if ($t30139 === true) {
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
          const $t30144 = (() => {
            {
              const $t30141 = (() => {
                {
                  const $t30140 = g2.ships;
                  {
                    const go_i5638 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                    return go$apply$4775(go_i5638, $t30140, 0);
                  }
                }
              })();
              {
                const $t30143 = (() => {
                  {
                    const $t30142 = game.ships;
                    {
                      const go_i5636 = { $: "$Clo_go$4775", _0: go$apply$4775 };
                      return go$apply$4775(go_i5636, $t30142, 0);
                    }
                  }
                })();
                return ($t30141 < $t30143);
              }
            }
          })();
          if ($t30144 === true) {
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
          const $t30149 = (() => {
            {
              const $t30146 = (() => {
                {
                  const $t30145 = game.shield;
                  return ($t30145 === 0);
                }
              })();
              {
                const $t30148 = (() => {
                  {
                    const $t30147 = g2.shield;
                    return ($t30147 > 0);
                  }
                })();
                return ($t30146 && $t30148);
              }
            }
          })();
          if ($t30149 === true) {
            return (() => {
              return Audio$beep(actx, 700., 0.06, "sine");
            })();
          } else {
            return {  };
          }
        }
      })();
      {
        const $t30152 = (() => {
          {
            const $t30150 = (() => {
              {
                const $t30095_i5634 = game.phase;
                switch ($t30095_i5634.$) {
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
              const $t30151 = (() => {
                {
                  const $t30096_i5632 = g2.phase;
                  switch ($t30096_i5632.$) {
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
              return ($t30150 && $t30151);
            }
          }
        })();
        if ($t30152 === true) {
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
      const $f30158 = taps._0;
      const $f30159 = taps._1;
      {
        const tap = (() => {
          return $f30158;
        })();
        {
          const tx = tap._0;
          {
            const col_w = (view_w / 3.);
            {
              const idx = (() => {
                {
                  const $t30154 = (() => {
                    {
                      const $t30153 = tx;
                      return ($t30153 / col_w);
                    }
                  })();
                  return Math.trunc($t30154);
                }
              })();
              {
                const $t30156 = (() => {
                  {
                    const $t30155 = (idx > 2);
                    if ($t30155 === true) {
                      return 2;
                    } else {
                      return idx;
                    }
                  }
                })();
                return { $: "Some", _0: $t30156 };
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
          const $p30182 = dom_window_size();
          {
            const win_w = $p30182._0;
            {
              const win_h = $p30182._1;
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
                        const $t30164 = game.phase;
                        switch ($t30164.$) {
                          case "Milestone": {
                            {
                              const $jp_clo30170 = (() => {
                                return { $: "$Clo_$jp30169$3840", _0: $jp30169$apply$3840, _1: cursor, _2: game, _3: keys, _4: taps, _5: view_h, _6: view_w };
                              })();
                              {
                                const $t30165 = (() => {
                                  {
                                    const $t28681_i5669 = { $: "$Clo_$lam28678$3761", _0: $lam28678$apply$3761 };
                                    return List$any$List_String$Fn_String_Bool(keys, $t28681_i5669);
                                  }
                                })();
                                if ($t30165 === true) {
                                  return (() => {
                                    {
                                      const $rc_642 = (() => {
                                        return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                                      })();
                                      return $rc_642;
                                    }
                                  })();
                                } else {
                                  return (() => {
                                    {
                                      const $t30167 = (() => {
                                        {
                                          const $rc_643 = milestone_tap_choice(taps, view_w, view_h);
                                          return $rc_643;
                                        }
                                      })();
                                      return Perihelion$Core$pick_milestone(game, $t30167);
                                    }
                                  })();
                                }
                              }
                            }
                            break;
                          }
                          default: {
                            {
                              const $rc_644 = (() => {
                                return Perihelion$Core$update(game, taps, keys, cursor, view_w, view_h, 0.0166667);
                              })();
                              return $rc_644;
                            }
                          }
                        }
                      }
                    })();
                    {
                      const muted2 = (() => {
                        {
                          const $t30171 = fx.muted;
                          {
                            const $t30115_i5667 = (() => {
                              {
                                const $t30114_i5666 = { $: "$Clo_$lam30111$3838", _0: $lam30111$apply$3838 };
                                return List$any$List_String$Fn_String_Bool(keys, $t30114_i5666);
                              }
                            })();
                            if ($t30115_i5667 === true) {
                              return (!$t30171);
                            } else {
                              return $t30171;
                            }
                          }
                        }
                      })();
                      (() => {
                        {
                          const $t30172 = fx.actx;
                          return play_sfx($t30172, muted2, game, g2);
                        }
                      })();
                      {
                        const fx1 = step_fx(fx, g2, 0.0166667);
                        {
                          const fx2 = ({ ...fx1, muted: muted2 });
                          (() => {
                            {
                              const $t30176 = (() => {
                                {
                                  const $t30174 = (() => {
                                    {
                                      const $t30095_i5663 = game.phase;
                                      switch ($t30095_i5663.$) {
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
                                    const $t30175 = (() => {
                                      {
                                        const $t30096_i5661 = g2.phase;
                                        switch ($t30096_i5661.$) {
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
                                    return ($t30174 && $t30175);
                                  }
                                }
                              })();
                              if ($t30176 === true) {
                                return (() => {
                                  {
                                    const $t30179 = (() => {
                                      {
                                        const $t30177 = g2.best;
                                        {
                                          const $t30178 = g2.runs;
                                          return Perihelion$Core$encode_save($t30177, $t30178);
                                        }
                                      }
                                    })();
                                    return Dom$store_set("perihelion.v1", $t30179);
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
                            const $t30181 = { $: "$Clo_$lam30180$3841", _0: $lam30180$apply$3841, _1: ctx, _2: el, _3: fx2, _4: g2 };
                            return Dom$on_frame($t30181);
                          }
                        }
                      }
                    }
                  }
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
    const $p30188 = dom_window_size();
    {
      const win_w = $p30188._0;
      {
        const win_h = $p30188._1;
        {
          const view_w = win_w;
          {
            const view_h = win_h;
            (() => {
              {
                const $t30183 = String(win_w);
                return Dom$set_attr(node, "width", $t30183);
              }
            })();
            (() => {
              {
                const $t30184 = String(win_h);
                return Dom$set_attr(node, "height", $t30184);
              }
            })();
            {
              const $t30186 = (() => {
                {
                  const $t30185 = boot_seed();
                  return Perihelion$Core$fresh_run($t30185, best, runs, view_w, view_h);
                }
              })();
              {
                const $t30187 = (() => {
                  {
                    const $t29468_i5670 = { $: "Nil" };
                    {
                      const $t29469_i5671 = { $: "Nil" };
                      {
                        const $t29470_i5672 = { $: "None" };
                        {
                          const $t29471_i5673 = audio_create();
                          return ({ trail: $t29468_i5670, t: 0., particles: $t29469_i5671, flash: $t29470_i5672, actx: $t29471_i5673, muted: false });
                        }
                      }
                    }
                  }
                })();
                return tick(ctx, node, $t30186, $t30187);
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
    const $t30189 = Dom$find("game-canvas");
    switch ($t30189.$) {
      case "None": {
        return println$String("no #game-canvas found");
        break;
      }
      case "Some": {
        const $f30197 = $t30189._0;
        {
          const node = $f30197;
          {
            const $t30190 = (() => {
              return Canvas$get_context(node);
            })();
            switch ($t30190.$) {
              case "None": {
                return println$String("2d context unavailable");
                break;
              }
              case "Some": {
                const $f30196 = $t30190._0;
                {
                  const ctx = $f30196;
                  {
                    const saved = (() => {
                      {
                        const $t30191 = Dom$store_get("perihelion.v1");
                        switch ($t30191.$) {
                          case "None": {
                            return "";
                            break;
                          }
                          case "Some": {
                            const $f30192 = $t30191._0;
                            {
                              const sv = $f30192;
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
                      const $p30195 = (() => {
                        {
                          const $rc_645 = Perihelion$Core$decode_save(saved);
                          return $rc_645;
                        }
                      })();
                      {
                        const best = $p30195._0;
                        {
                          const runs = $p30195._1;
                          {
                            const $t30194 = (() => {
                              return { $: "$Clo_$lam30193$3842", _0: $lam30193$apply$3842, _1: best, _2: ctx, _3: node, _4: runs };
                            })();
                            return Dom$on_frame($t30194);
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
        const $rc_657 = march_print(x);
        return $rc_657;
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

function $lam27733$apply$3695($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27734 = g1.asteroids;
        {
          const $t27735 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27734, $t27735);
        }
      }
    }
  }
}
const $lam27733$apply$3695$clo = { _0: ($_, $clo, s) => $lam27733$apply$3695($clo, s) };

function $lam27738$apply$3696($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27740 = (() => {
        {
          const $t27739 = s.ttl;
          return ($t27739 > 0.);
        }
      })();
      {
        const $t27743 = (() => {
          {
            const $t27741 = s.x;
            {
              const $t27742 = s.y;
              return Perihelion$Combat$in_band(g1, $t27741, $t27742);
            }
          }
        })();
        return ($t27740 && $t27743);
      }
    }
  }
}
const $lam27738$apply$3696$clo = { _0: ($_, $clo, s) => $lam27738$apply$3696($clo, s) };

function $lam27746$apply$3697($clo, s) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const g1 = (() => {
        return $clo._2;
      })();
      {
        const $t27747 = g1.asteroids;
        {
          const $t27748 = g1.ships;
          return Perihelion$Combat$age_shot(s, dt_s, $t27747, $t27748);
        }
      }
    }
  }
}
const $lam27746$apply$3697$clo = { _0: ($_, $clo, s) => $lam27746$apply$3697($clo, s) };

function $lam27751$apply$3698($clo, s) {
  {
    const g1 = (() => {
      return $clo._1;
    })();
    {
      const $t27753 = (() => {
        {
          const $t27752 = s.ttl;
          return ($t27752 > 0.);
        }
      })();
      {
        const $t27756 = (() => {
          {
            const $t27754 = s.x;
            {
              const $t27755 = s.y;
              return Perihelion$Combat$in_band(g1, $t27754, $t27755);
            }
          }
        })();
        return ($t27753 && $t27756);
      }
    }
  }
}
const $lam27751$apply$3698$clo = { _0: ($_, $clo, s) => $lam27751$apply$3698($clo, s) };

function $lam27759$apply$3699($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t27761 = (() => {
        {
          const $t27760 = p.ttl;
          return ($t27760 - dt_s);
        }
      })();
      return ({ ...p, ttl: $t27761 });
    }
  }
}
const $lam27759$apply$3699$clo = { _0: ($_, $clo, p) => $lam27759$apply$3699($clo, p) };

function $lam27764$apply$3700($clo, p) {
  {
    const $t27765 = p.ttl;
    return ($t27765 > 0.);
  }
}
const $lam27764$apply$3700$clo = { _0: ($_, $clo, p) => $lam27764$apply$3700($clo, p) };

function $lam28164$apply$3716($clo, k) {
  return (k === " ");
}
const $lam28164$apply$3716$clo = { _0: ($_, $clo, k) => $lam28164$apply$3716($clo, k) };

function $lam28232$apply$3719($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28233 = sh.star_idx;
      return ($t28233 !== tidx);
    }
  }
}
const $lam28232$apply$3719$clo = { _0: ($_, $clo, sh) => $lam28232$apply$3719($clo, sh) };

function $lam28236$apply$3720($clo, sh) {
  {
    const tidx = (() => {
      return $clo._1;
    })();
    {
      const $t28238 = (() => {
        {
          const $t28237 = sh.star_idx;
          return ($t28237 > tidx);
        }
      })();
      if ($t28238 === true) {
        return (() => {
          {
            const $t28240 = (() => {
              {
                const $t28239 = sh.star_idx;
                return ($t28239 - 1);
              }
            })();
            return ({ ...sh, star_idx: $t28240 });
          }
        })();
      } else {
        return sh;
      }
    }
  }
}
const $lam28236$apply$3720$clo = { _0: ($_, $clo, sh) => $lam28236$apply$3720($clo, sh) };

function $lam28253$apply$3722($clo, s) {
  return s.star_killer;
}
const $lam28253$apply$3722$clo = { _0: ($_, $clo, s) => $lam28253$apply$3722($clo, s) };

function $lam28266$apply$3724($clo, sh) {
  {
    const $t28267 = sh.star_killer;
    return (!$t28267);
  }
}
const $lam28266$apply$3724$clo = { _0: ($_, $clo, sh) => $lam28266$apply$3724($clo, sh) };

function $lam28273$apply$3725($clo, sh) {
  {
    const $t28274 = sh.star_killer;
    return (!$t28274);
  }
}
const $lam28273$apply$3725$clo = { _0: ($_, $clo, sh) => $lam28273$apply$3725($clo, sh) };

function $lam28287$apply$3726($clo, a) {
  {
    const $t28288 = a.x;
    {
      const $t28289 = a.y;
      return { _0: $t28288, _1: $t28289 };
    }
  }
}
const $lam28287$apply$3726$clo = { _0: ($_, $clo, a) => $lam28287$apply$3726($clo, a) };

function $lam28292$apply$3727($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28293 = game.player_shots;
      {
        const $t28298 = { $: "$Clo_$lam28294$3728", _0: $lam28294$apply$3728, _1: a };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28293, $t28298);
      }
    }
  }
}
const $lam28292$apply$3727$clo = { _0: ($_, $clo, a) => $lam28292$apply$3727($clo, a) };

function $lam28294$apply$3728($clo, s) {
  {
    const a = (() => {
      return $clo._1;
    })();
    {
      const $t28295 = a.x;
      {
        const $t28296 = a.y;
        {
          const $t28297 = a.radius;
          {
            const $t28284_i9605 = s.x;
            {
              const $t28285_i9606 = s.y;
              {
                const $t27602_i12363 = (() => {
                  {
                    const dx_i4539_i12359 = ($t28295 - $t28284_i9605);
                    {
                      const dy_i4540_i12360 = ($t28296 - $t28285_i9606);
                      {
                        const $t27600_i4541_i12361 = (dx_i4539_i12359 * dx_i4539_i12359);
                        {
                          const $t27601_i4542_i12362 = (dy_i4540_i12360 * dy_i4540_i12360);
                          return ($t27600_i4541_i12361 + $t27601_i4542_i12362);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i12366 = (() => {
                    {
                      const $t27603_i12364 = (3. + $t28297);
                      {
                        const $t27604_i12365 = (3. + $t28297);
                        return ($t27603_i12364 * $t27604_i12365);
                      }
                    }
                  })();
                  return ($t27602_i12363 <= $t27605_i12366);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28294$apply$3728$clo = { _0: ($_, $clo, s) => $lam28294$apply$3728($clo, s) };

function $lam28301$apply$3729($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28308 = (() => {
        {
          const $t28302 = game.asteroids;
          {
            const $t28307 = { $: "$Clo_$lam28303$3730", _0: $lam28303$apply$3730, _1: s };
            return List$any$List_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_mode_AsteroidMode_radius_Float_shape_seed_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28302, $t28307);
          }
        }
      })();
      return (!$t28308);
    }
  }
}
const $lam28301$apply$3729$clo = { _0: ($_, $clo, s) => $lam28301$apply$3729($clo, s) };

function $lam28303$apply$3730($clo, a) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const $t28304 = a.x;
      {
        const $t28305 = a.y;
        {
          const $t28306 = a.radius;
          {
            const $t28284_i9612 = s.x;
            {
              const $t28285_i9613 = s.y;
              {
                const $t27602_i12377 = (() => {
                  {
                    const dx_i4539_i12373 = ($t28304 - $t28284_i9612);
                    {
                      const dy_i4540_i12374 = ($t28305 - $t28285_i9613);
                      {
                        const $t27600_i4541_i12375 = (dx_i4539_i12373 * dx_i4539_i12373);
                        {
                          const $t27601_i4542_i12376 = (dy_i4540_i12374 * dy_i4540_i12374);
                          return ($t27600_i4541_i12375 + $t27601_i4542_i12376);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i12380 = (() => {
                    {
                      const $t27603_i12378 = (3. + $t28306);
                      {
                        const $t27604_i12379 = (3. + $t28306);
                        return ($t27603_i12378 * $t27604_i12379);
                      }
                    }
                  })();
                  return ($t27602_i12377 <= $t27605_i12380);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28303$apply$3730$clo = { _0: ($_, $clo, a) => $lam28303$apply$3730($clo, a) };

function $lam28320$apply$3731($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28321 = game.player_shots;
      {
        const $t28323 = { $: "$Clo_$lam28322$3732", _0: $lam28322$apply$3732, _1: sh };
        return List$any$List_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float$Fn_R_homing_Bool_star_killer_Bool_target_x_Float_target_y_Float_ttl_Float_vx_Float_vy_Float_x_Float_y_Float_Bool($t28321, $t28323);
      }
    }
  }
}
const $lam28320$apply$3731$clo = { _0: ($_, $clo, sh) => $lam28320$apply$3731($clo, sh) };

function $lam28322$apply$3732($clo, s) {
  {
    const sh = (() => {
      return $clo._1;
    })();
    {
      const pos_i9617 = (() => {
        {
          const pos_i12394 = (() => {
            {
              const $t27598_i12392 = sh.x;
              {
                const $t27599_i12393 = sh.y;
                return { _0: $t27598_i12392, _1: $t27599_i12393 };
              }
            }
          })();
          return pos_i12394;
        }
      })();
      {
        const sx_i9619 = pos_i9617._0;
        {
          const sy_i9620 = pos_i9617._1;
          {
            const $t28284_i12385 = s.x;
            {
              const $t28285_i12386 = s.y;
              {
                const $t27602_i4836_i12387 = (() => {
                  {
                    const dx_i12806 = (sx_i9619 - $t28284_i12385);
                    {
                      const dy_i12807 = (sy_i9620 - $t28285_i12386);
                      {
                        const $t27600_i12808 = (dx_i12806 * dx_i12806);
                        {
                          const $t27601_i12809 = (dy_i12807 * dy_i12807);
                          return ($t27600_i12808 + $t27601_i12809);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i4839_i12390 = (() => {
                    {
                      const $t27603_i4837_i12388 = (3. + 10.);
                      {
                        const $t27604_i4838_i12389 = (3. + 10.);
                        return ($t27603_i4837_i12388 * $t27604_i4838_i12389);
                      }
                    }
                  })();
                  return ($t27602_i4836_i12387 <= $t27605_i4839_i12390);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28322$apply$3732$clo = { _0: ($_, $clo, s) => $lam28322$apply$3732($clo, s) };

function $lam28326$apply$3733($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28330 = (() => {
        {
          const $t28327 = game.ships;
          {
            const $t28329 = { $: "$Clo_$lam28328$3734", _0: $lam28328$apply$3734, _1: s };
            return List$any$List_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float$Fn_R_fire_cooldown_Float_hunter_Bool_idle_timer_Float_mode_ShipMode_star_idx_Int_x_Float_y_Float_Bool($t28327, $t28329);
          }
        }
      })();
      return (!$t28330);
    }
  }
}
const $lam28326$apply$3733$clo = { _0: ($_, $clo, s) => $lam28326$apply$3733($clo, s) };

function $lam28328$apply$3734($clo, sh) {
  {
    const s = (() => {
      return $clo._1;
    })();
    {
      const pos_i9624 = (() => {
        {
          const pos_i12408 = (() => {
            {
              const $t27598_i12406 = sh.x;
              {
                const $t27599_i12407 = sh.y;
                return { _0: $t27598_i12406, _1: $t27599_i12407 };
              }
            }
          })();
          return pos_i12408;
        }
      })();
      {
        const sx_i9626 = pos_i9624._0;
        {
          const sy_i9627 = pos_i9624._1;
          {
            const $t28284_i12399 = s.x;
            {
              const $t28285_i12400 = s.y;
              {
                const $t27602_i4836_i12401 = (() => {
                  {
                    const dx_i12814 = (sx_i9626 - $t28284_i12399);
                    {
                      const dy_i12815 = (sy_i9627 - $t28285_i12400);
                      {
                        const $t27600_i12816 = (dx_i12814 * dx_i12814);
                        {
                          const $t27601_i12817 = (dy_i12815 * dy_i12815);
                          return ($t27600_i12816 + $t27601_i12817);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i4839_i12404 = (() => {
                    {
                      const $t27603_i4837_i12402 = (3. + 10.);
                      {
                        const $t27604_i4838_i12403 = (3. + 10.);
                        return ($t27603_i4837_i12402 * $t27604_i4838_i12403);
                      }
                    }
                  })();
                  return ($t27602_i4836_i12401 <= $t27605_i4839_i12404);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28328$apply$3734$clo = { _0: ($_, $clo, sh) => $lam28328$apply$3734($clo, sh) };

function $lam28377$apply$3736($clo, p) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28370_i9632 = p.x;
      {
        const $t28371_i9633 = p.y;
        {
          const $t28373_i9635 = game.ball_x;
          {
            const $t28374_i9636 = game.ball_y;
            {
              const $t27602_i12419 = (() => {
                {
                  const dx_i4539_i12415 = ($t28373_i9635 - $t28370_i9632);
                  {
                    const dy_i4540_i12416 = ($t28374_i9636 - $t28371_i9633);
                    {
                      const $t27600_i4541_i12417 = (dx_i4539_i12415 * dx_i4539_i12415);
                      {
                        const $t27601_i4542_i12418 = (dy_i4540_i12416 * dy_i4540_i12416);
                        return ($t27600_i4541_i12417 + $t27601_i4542_i12418);
                      }
                    }
                  }
                }
              })();
              {
                const $t27605_i12422 = (() => {
                  {
                    const $t27603_i12420 = (12. + 6.);
                    {
                      const $t27604_i12421 = (12. + 6.);
                      return ($t27603_i12420 * $t27604_i12421);
                    }
                  }
                })();
                return ($t27602_i12419 <= $t27605_i12422);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28377$apply$3736$clo = { _0: ($_, $clo, p) => $lam28377$apply$3736($clo, p) };

function $lam28381$apply$3737($clo, q) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28382 = (() => {
        {
          const $t28370_i9640 = q.x;
          {
            const $t28371_i9641 = q.y;
            {
              const $t28373_i9643 = game.ball_x;
              {
                const $t28374_i9644 = game.ball_y;
                {
                  const $t27602_i12433 = (() => {
                    {
                      const dx_i4539_i12429 = ($t28373_i9643 - $t28370_i9640);
                      {
                        const dy_i4540_i12430 = ($t28374_i9644 - $t28371_i9641);
                        {
                          const $t27600_i4541_i12431 = (dx_i4539_i12429 * dx_i4539_i12429);
                          {
                            const $t27601_i4542_i12432 = (dy_i4540_i12430 * dy_i4540_i12430);
                            return ($t27600_i4541_i12431 + $t27601_i4542_i12432);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27605_i12436 = (() => {
                      {
                        const $t27603_i12434 = (12. + 6.);
                        {
                          const $t27604_i12435 = (12. + 6.);
                          return ($t27603_i12434 * $t27604_i12435);
                        }
                      }
                    })();
                    return ($t27602_i12433 <= $t27605_i12436);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28382);
    }
  }
}
const $lam28381$apply$3737$clo = { _0: ($_, $clo, q) => $lam28381$apply$3737($clo, q) };

function $jp28399$apply$3738($clo) {
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
          const $t28397 = (() => {
            {
              const $t28396 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28396);
            }
          })();
          return ({ ...$t28397, pickups: remaining });
        }
      }
    }
  }
}
const $jp28399$apply$3738$clo = { _0: ($_, $clo) => $jp28399$apply$3738($clo) };

function $jp28403$apply$3739($clo) {
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
          const $t28397 = (() => {
            {
              const $t28396 = p.kind;
              return Perihelion$Core$apply_upgrade(game, $t28396);
            }
          })();
          return ({ ...$t28397, pickups: remaining });
        }
      }
    }
  }
}
const $jp28403$apply$3739$clo = { _0: ($_, $clo) => $jp28403$apply$3739($clo) };

function $lam28424$apply$3740($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28417_i9648 = game.ball_x;
      {
        const $t28418_i9649 = game.ball_y;
        {
          const $t28284_i12441 = s.x;
          {
            const $t28285_i12442 = s.y;
            {
              const $t27602_i4836_i12443 = (() => {
                {
                  const dx_i12822 = ($t28417_i9648 - $t28284_i12441);
                  {
                    const dy_i12823 = ($t28418_i9649 - $t28285_i12442);
                    {
                      const $t27600_i12824 = (dx_i12822 * dx_i12822);
                      {
                        const $t27601_i12825 = (dy_i12823 * dy_i12823);
                        return ($t27600_i12824 + $t27601_i12825);
                      }
                    }
                  }
                }
              })();
              {
                const $t27605_i4839_i12446 = (() => {
                  {
                    const $t27603_i4837_i12444 = (3. + 6.);
                    {
                      const $t27604_i4838_i12445 = (3. + 6.);
                      return ($t27603_i4837_i12444 * $t27604_i4838_i12445);
                    }
                  }
                })();
                return ($t27602_i4836_i12443 <= $t27605_i4839_i12446);
              }
            }
          }
        }
      }
    }
  }
}
const $lam28424$apply$3740$clo = { _0: ($_, $clo, s) => $lam28424$apply$3740($clo, s) };

function $lam28429$apply$3741($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28430 = (() => {
        {
          const $t28417_i9653 = game.ball_x;
          {
            const $t28418_i9654 = game.ball_y;
            {
              const $t28284_i12451 = s.x;
              {
                const $t28285_i12452 = s.y;
                {
                  const $t27602_i4836_i12453 = (() => {
                    {
                      const dx_i12830 = ($t28417_i9653 - $t28284_i12451);
                      {
                        const dy_i12831 = ($t28418_i9654 - $t28285_i12452);
                        {
                          const $t27600_i12832 = (dx_i12830 * dx_i12830);
                          {
                            const $t27601_i12833 = (dy_i12831 * dy_i12831);
                            return ($t27600_i12832 + $t27601_i12833);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27605_i4839_i12456 = (() => {
                      {
                        const $t27603_i4837_i12454 = (3. + 6.);
                        {
                          const $t27604_i4838_i12455 = (3. + 6.);
                          return ($t27603_i4837_i12454 * $t27604_i4838_i12455);
                        }
                      }
                    })();
                    return ($t27602_i4836_i12453 <= $t27605_i4839_i12456);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28430);
    }
  }
}
const $lam28429$apply$3741$clo = { _0: ($_, $clo, s) => $lam28429$apply$3741($clo, s) };

function $lam28434$apply$3742($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28411_i9658 = a.x;
      {
        const $t28412_i9659 = a.y;
        {
          const $t28413_i9660 = a.radius;
          {
            const $t28414_i9661 = game.ball_x;
            {
              const $t28415_i9662 = game.ball_y;
              {
                const $t27602_i12467 = (() => {
                  {
                    const dx_i4539_i12463 = ($t28414_i9661 - $t28411_i9658);
                    {
                      const dy_i4540_i12464 = ($t28415_i9662 - $t28412_i9659);
                      {
                        const $t27600_i4541_i12465 = (dx_i4539_i12463 * dx_i4539_i12463);
                        {
                          const $t27601_i4542_i12466 = (dy_i4540_i12464 * dy_i4540_i12464);
                          return ($t27600_i4541_i12465 + $t27601_i4542_i12466);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i12470 = (() => {
                    {
                      const $t27603_i12468 = ($t28413_i9660 + 6.);
                      {
                        const $t27604_i12469 = ($t28413_i9660 + 6.);
                        return ($t27603_i12468 * $t27604_i12469);
                      }
                    }
                  })();
                  return ($t27602_i12467 <= $t27605_i12470);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28434$apply$3742$clo = { _0: ($_, $clo, a) => $lam28434$apply$3742($clo, a) };

function $lam28437$apply$3743($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const pos_i9666 = (() => {
        {
          const pos_i12488 = (() => {
            {
              const $t27598_i12486 = sh.x;
              {
                const $t27599_i12487 = sh.y;
                return { _0: $t27598_i12486, _1: $t27599_i12487 };
              }
            }
          })();
          return pos_i12488;
        }
      })();
      {
        const sx_i9668 = pos_i9666._0;
        {
          const sy_i9669 = pos_i9666._1;
          {
            const $t28407_i9671 = game.ball_x;
            {
              const $t28408_i9672 = game.ball_y;
              {
                const $t27602_i12481 = (() => {
                  {
                    const dx_i4539_i12477 = ($t28407_i9671 - sx_i9668);
                    {
                      const dy_i4540_i12478 = ($t28408_i9672 - sy_i9669);
                      {
                        const $t27600_i4541_i12479 = (dx_i4539_i12477 * dx_i4539_i12477);
                        {
                          const $t27601_i4542_i12480 = (dy_i4540_i12478 * dy_i4540_i12478);
                          return ($t27600_i4541_i12479 + $t27601_i4542_i12480);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i12484 = (() => {
                    {
                      const $t27603_i12482 = (10. + 6.);
                      {
                        const $t27604_i12483 = (10. + 6.);
                        return ($t27603_i12482 * $t27604_i12483);
                      }
                    }
                  })();
                  return ($t27602_i12481 <= $t27605_i12484);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28437$apply$3743$clo = { _0: ($_, $clo, sh) => $lam28437$apply$3743($clo, sh) };

function $lam28453$apply$3744($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28411_i9676 = a.x;
      {
        const $t28412_i9677 = a.y;
        {
          const $t28413_i9678 = a.radius;
          {
            const $t28414_i9679 = game.ball_x;
            {
              const $t28415_i9680 = game.ball_y;
              {
                const $t27602_i12499 = (() => {
                  {
                    const dx_i4539_i12495 = ($t28414_i9679 - $t28411_i9676);
                    {
                      const dy_i4540_i12496 = ($t28415_i9680 - $t28412_i9677);
                      {
                        const $t27600_i4541_i12497 = (dx_i4539_i12495 * dx_i4539_i12495);
                        {
                          const $t27601_i4542_i12498 = (dy_i4540_i12496 * dy_i4540_i12496);
                          return ($t27600_i4541_i12497 + $t27601_i4542_i12498);
                        }
                      }
                    }
                  }
                })();
                {
                  const $t27605_i12502 = (() => {
                    {
                      const $t27603_i12500 = ($t28413_i9678 + 6.);
                      {
                        const $t27604_i12501 = ($t28413_i9678 + 6.);
                        return ($t27603_i12500 * $t27604_i12501);
                      }
                    }
                  })();
                  return ($t27602_i12499 <= $t27605_i12502);
                }
              }
            }
          }
        }
      }
    }
  }
}
const $lam28453$apply$3744$clo = { _0: ($_, $clo, a) => $lam28453$apply$3744($clo, a) };

function $lam28458$apply$3745($clo, a) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28459 = (() => {
        {
          const $t28411_i9684 = a.x;
          {
            const $t28412_i9685 = a.y;
            {
              const $t28413_i9686 = a.radius;
              {
                const $t28414_i9687 = game.ball_x;
                {
                  const $t28415_i9688 = game.ball_y;
                  {
                    const $t27602_i12513 = (() => {
                      {
                        const dx_i4539_i12509 = ($t28414_i9687 - $t28411_i9684);
                        {
                          const dy_i4540_i12510 = ($t28415_i9688 - $t28412_i9685);
                          {
                            const $t27600_i4541_i12511 = (dx_i4539_i12509 * dx_i4539_i12509);
                            {
                              const $t27601_i4542_i12512 = (dy_i4540_i12510 * dy_i4540_i12510);
                              return ($t27600_i4541_i12511 + $t27601_i4542_i12512);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27605_i12516 = (() => {
                        {
                          const $t27603_i12514 = ($t28413_i9686 + 6.);
                          {
                            const $t27604_i12515 = ($t28413_i9686 + 6.);
                            return ($t27603_i12514 * $t27604_i12515);
                          }
                        }
                      })();
                      return ($t27602_i12513 <= $t27605_i12516);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28459);
    }
  }
}
const $lam28458$apply$3745$clo = { _0: ($_, $clo, a) => $lam28458$apply$3745($clo, a) };

function $lam28463$apply$3746($clo, s) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28464 = (() => {
        {
          const $t28417_i9692 = game.ball_x;
          {
            const $t28418_i9693 = game.ball_y;
            {
              const $t28284_i12521 = s.x;
              {
                const $t28285_i12522 = s.y;
                {
                  const $t27602_i4836_i12523 = (() => {
                    {
                      const dx_i12838 = ($t28417_i9692 - $t28284_i12521);
                      {
                        const dy_i12839 = ($t28418_i9693 - $t28285_i12522);
                        {
                          const $t27600_i12840 = (dx_i12838 * dx_i12838);
                          {
                            const $t27601_i12841 = (dy_i12839 * dy_i12839);
                            return ($t27600_i12840 + $t27601_i12841);
                          }
                        }
                      }
                    }
                  })();
                  {
                    const $t27605_i4839_i12526 = (() => {
                      {
                        const $t27603_i4837_i12524 = (3. + 6.);
                        {
                          const $t27604_i4838_i12525 = (3. + 6.);
                          return ($t27603_i4837_i12524 * $t27604_i4838_i12525);
                        }
                      }
                    })();
                    return ($t27602_i4836_i12523 <= $t27605_i4839_i12526);
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28464);
    }
  }
}
const $lam28463$apply$3746$clo = { _0: ($_, $clo, s) => $lam28463$apply$3746($clo, s) };

function $lam28468$apply$3747($clo, sh) {
  {
    const game = (() => {
      return $clo._1;
    })();
    {
      const $t28469 = (() => {
        {
          const pos_i9697 = (() => {
            {
              const pos_i12544 = (() => {
                {
                  const $t27598_i12542 = sh.x;
                  {
                    const $t27599_i12543 = sh.y;
                    return { _0: $t27598_i12542, _1: $t27599_i12543 };
                  }
                }
              })();
              return pos_i12544;
            }
          })();
          {
            const sx_i9699 = pos_i9697._0;
            {
              const sy_i9700 = pos_i9697._1;
              {
                const $t28407_i9702 = game.ball_x;
                {
                  const $t28408_i9703 = game.ball_y;
                  {
                    const $t27602_i12537 = (() => {
                      {
                        const dx_i4539_i12533 = ($t28407_i9702 - sx_i9699);
                        {
                          const dy_i4540_i12534 = ($t28408_i9703 - sy_i9700);
                          {
                            const $t27600_i4541_i12535 = (dx_i4539_i12533 * dx_i4539_i12533);
                            {
                              const $t27601_i4542_i12536 = (dy_i4540_i12534 * dy_i4540_i12534);
                              return ($t27600_i4541_i12535 + $t27601_i4542_i12536);
                            }
                          }
                        }
                      }
                    })();
                    {
                      const $t27605_i12540 = (() => {
                        {
                          const $t27603_i12538 = (10. + 6.);
                          {
                            const $t27604_i12539 = (10. + 6.);
                            return ($t27603_i12538 * $t27604_i12539);
                          }
                        }
                      })();
                      return ($t27602_i12537 <= $t27605_i12540);
                    }
                  }
                }
              }
            }
          }
        }
      })();
      return (!$t28469);
    }
  }
}
const $lam28468$apply$3747$clo = { _0: ($_, $clo, sh) => $lam28468$apply$3747($clo, sh) };

function $lam28550$apply$3748($clo, k) {
  {
    const $t28551 = (() => {
      return (k === "w");
    })();
    {
      const $t28552 = (k === "W");
      return ($t28551 || $t28552);
    }
  }
}
const $lam28550$apply$3748$clo = { _0: ($_, $clo, k) => $lam28550$apply$3748($clo, k) };

function $lam28554$apply$3749($clo, k) {
  {
    const $t28555 = (() => {
      return (k === "s");
    })();
    {
      const $t28556 = (k === "S");
      return ($t28555 || $t28556);
    }
  }
}
const $lam28554$apply$3749$clo = { _0: ($_, $clo, k) => $lam28554$apply$3749($clo, k) };

function $lam28569$apply$3750($clo, k) {
  {
    const $t28570 = (() => {
      return (k === "e");
    })();
    {
      const $t28571 = (k === "E");
      return ($t28570 || $t28571);
    }
  }
}
const $lam28569$apply$3750$clo = { _0: ($_, $clo, k) => $lam28569$apply$3750($clo, k) };

function $lam28573$apply$3751($clo, k) {
  {
    const $t28574 = (() => {
      return (k === "q");
    })();
    {
      const $t28575 = (k === "Q");
      return ($t28574 || $t28575);
    }
  }
}
const $lam28573$apply$3751$clo = { _0: ($_, $clo, k) => $lam28573$apply$3751($clo, k) };

function $lam28581$apply$3752($clo, k) {
  {
    const $t28582 = (() => {
      return (k === "d");
    })();
    {
      const $t28583 = (k === "D");
      return ($t28582 || $t28583);
    }
  }
}
const $lam28581$apply$3752$clo = { _0: ($_, $clo, k) => $lam28581$apply$3752($clo, k) };

function $lam28585$apply$3753($clo, k) {
  {
    const $t28586 = (() => {
      return (k === "w");
    })();
    {
      const $t28587 = (k === "W");
      return ($t28586 || $t28587);
    }
  }
}
const $lam28585$apply$3753$clo = { _0: ($_, $clo, k) => $lam28585$apply$3753($clo, k) };

function $lam28638$apply$3756($clo, k) {
  {
    const $t28639 = (() => {
      return (k === "x");
    })();
    {
      const $t28640 = (k === "X");
      return ($t28639 || $t28640);
    }
  }
}
const $lam28638$apply$3756$clo = { _0: ($_, $clo, k) => $lam28638$apply$3756($clo, k) };

function $lam28678$apply$3761($clo, k) {
  {
    const $t28679 = (() => {
      return (k === "r");
    })();
    {
      const $t28680 = (k === "R");
      return ($t28679 || $t28680);
    }
  }
}
const $lam28678$apply$3761$clo = { _0: ($_, $clo, k) => $lam28678$apply$3761($clo, k) };

function $jp28991$apply$3773($clo) {
  {
    const $f28986 = (() => {
      return $clo._1;
    })();
    {
      const fallback = (() => {
        return $clo._2;
      })();
      {
        const rest = (() => {
          return $f28986;
        })();
        return Perihelion$Core$top_star(rest, fallback);
      }
    }
  }
}
const $jp28991$apply$3773$clo = { _0: ($_, $clo) => $jp28991$apply$3773($clo) };

function $lam29193$apply$3785($clo, r) {
  return Perihelion$Core$encode_run(r);
}
const $lam29193$apply$3785$clo = { _0: ($_, $clo, r) => $lam29193$apply$3785($clo, r) };

function $jp29207$apply$3786($clo) {
  return { $: "None" };
}
const $jp29207$apply$3786$clo = { _0: ($_, $clo) => $jp29207$apply$3786($clo) };

function $jp29211$apply$3787($clo) {
  {
    const $jp_clo29208 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29210 = (() => {
        return { $: "$Clo_$jp29209$3788", _0: $jp29209$apply$3788, _1: $jp_clo29208 };
      })();
      return $jp29209$apply$3788($jp_clo29210);
    }
  }
}
const $jp29211$apply$3787$clo = { _0: ($_, $clo) => $jp29211$apply$3787($clo) };

function $jp29209$apply$3788($clo) {
  {
    const $jp_clo29208 = (() => {
      return $clo._1;
    })();
    return $jp_clo29208._0($jp_clo29208);
  }
}
const $jp29209$apply$3788$clo = { _0: ($_, $clo) => $jp29209$apply$3788($clo) };

function $jp29215$apply$3789($clo) {
  {
    const $jp_clo29212 = (() => {
      return $clo._1;
    })();
    return $jp_clo29212._0($jp_clo29212);
  }
}
const $jp29215$apply$3789$clo = { _0: ($_, $clo) => $jp29215$apply$3789($clo) };

function $jp29219$apply$3790($clo) {
  {
    const $jp_clo29216 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29218 = (() => {
        return { $: "$Clo_$jp29217$3791", _0: $jp29217$apply$3791, _1: $jp_clo29216 };
      })();
      return $jp29217$apply$3791($jp_clo29218);
    }
  }
}
const $jp29219$apply$3790$clo = { _0: ($_, $clo) => $jp29219$apply$3790($clo) };

function $jp29217$apply$3791($clo) {
  {
    const $jp_clo29216 = (() => {
      return $clo._1;
    })();
    return $jp_clo29216._0($jp_clo29216);
  }
}
const $jp29217$apply$3791$clo = { _0: ($_, $clo) => $jp29217$apply$3791($clo) };

function $jp29223$apply$3792($clo) {
  {
    const $jp_clo29220 = (() => {
      return $clo._1;
    })();
    return $jp_clo29220._0($jp_clo29220);
  }
}
const $jp29223$apply$3792$clo = { _0: ($_, $clo) => $jp29223$apply$3792($clo) };

function $jp29227$apply$3793($clo) {
  {
    const $jp_clo29224 = (() => {
      return $clo._1;
    })();
    {
      const $jp_clo29226 = (() => {
        return { $: "$Clo_$jp29225$3794", _0: $jp29225$apply$3794, _1: $jp_clo29224 };
      })();
      return $jp29225$apply$3794($jp_clo29226);
    }
  }
}
const $jp29227$apply$3793$clo = { _0: ($_, $clo) => $jp29227$apply$3793($clo) };

function $jp29225$apply$3794($clo) {
  {
    const $jp_clo29224 = (() => {
      return $clo._1;
    })();
    return $jp_clo29224._0($jp_clo29224);
  }
}
const $jp29225$apply$3794$clo = { _0: ($_, $clo) => $jp29225$apply$3794($clo) };

function $lam29417$apply$3803($clo, u) {
  {
    const owned = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "OffenseWeapon": {
        const $f29419 = u._0;
        {
          const k = $f29419;
          {
            const $t29418 = (() => {
              {
                const $t690_i9731 = { $: "$Clo_$lam689$4780", _0: $lam689$apply$4780, _1: k };
                return List$any$List_WeaponKind$Fn_WeaponKind_Bool(owned, $t690_i9731);
              }
            })();
            return (!$t29418);
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
const $lam29417$apply$3803$clo = { _0: ($_, $clo, u) => $lam29417$apply$3803($clo, u) };

function $lam29455$apply$3804($clo, u) {
  {
    const k = (() => {
      return $clo._1;
    })();
    switch (u.$) {
      case "SpecialItem": {
        const $f29456 = u._0;
        {
          const sk = $f29456;
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
const $lam29455$apply$3804$clo = { _0: ($_, $clo, u) => $lam29455$apply$3804($clo, u) };

function $lam29513$apply$3806($clo, p) {
  {
    const dt_s = (() => {
      return $clo._1;
    })();
    {
      const $t29506_i9738 = (() => {
        {
          const $t29503_i9735 = p.x;
          {
            const $t29505_i9737 = (() => {
              {
                const $t29504_i9736 = p.vx;
                return ($t29504_i9736 * dt_s);
              }
            })();
            return ($t29503_i9735 + $t29505_i9737);
          }
        }
      })();
      {
        const $t29510_i9742 = (() => {
          {
            const $t29507_i9739 = p.y;
            {
              const $t29509_i9741 = (() => {
                {
                  const $t29508_i9740 = p.vy;
                  return ($t29508_i9740 * dt_s);
                }
              })();
              return ($t29507_i9739 + $t29509_i9741);
            }
          }
        })();
        {
          const $t29512_i9744 = (() => {
            {
              const $t29511_i9743 = p.life;
              return ($t29511_i9743 - dt_s);
            }
          })();
          return ({ ...p, x: $t29506_i9738, y: $t29510_i9742, life: $t29512_i9744 });
        }
      }
    }
  }
}
const $lam29513$apply$3806$clo = { _0: ($_, $clo, p) => $lam29513$apply$3806($clo, p) };

function $lam29516$apply$3807($clo, p) {
  {
    const $t29517 = p.life;
    return ($t29517 > 0.);
  }
}
const $lam29516$apply$3807$clo = { _0: ($_, $clo, p) => $lam29516$apply$3807($clo, p) };

function $jp29662$apply$3810($clo) {
  {
    const $f29656 = (() => {
      return $clo._1;
    })();
    {
      const $f29657 = (() => {
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
              return $f29657;
            })();
            {
              const o = (() => {
                return $f29656;
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
                  const $t29652 = s.x;
                  {
                    const $t29653 = s.y;
                    {
                      const $t29654 = o.radius;
                      return Canvas$arc(ctx, $t29652, $t29653, $t29654, 0., 6.28318530718);
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
const $jp29662$apply$3810$clo = { _0: ($_, $clo) => $jp29662$apply$3810($clo) };

function $jp29701$apply$3813($clo) {
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
          const $t29700 = (() => {
            {
              const $t29606_i9755 = (() => {
                {
                  const $t29605_i9754 = (() => {
                    {
                      const $t29604_i9753 = (() => {
                        {
                          const $t29601_i9750 = (() => {
                            {
                              const $t29600_i9749 = s.x;
                              return ($t29600_i9749 + 4.);
                            }
                          })();
                          {
                            const $t29603_i9752 = (() => {
                              {
                                const $t29602_i9751 = s.y;
                                return ($t29602_i9751 + 4.);
                              }
                            })();
                            {
                              const x_i12551 = (() => {
                                {
                                  const $t29475_i12550 = (() => {
                                    {
                                      const $t29474_i12549 = (() => {
                                        {
                                          const $t29472_i12547 = ($t29601_i9750 * 12.9898);
                                          {
                                            const $t29473_i12548 = ($t29603_i9752 * 78.233);
                                            return ($t29472_i12547 + $t29473_i12548);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29474_i12549);
                                    }
                                  })();
                                  return ($t29475_i12550 * 43758.5453);
                                }
                              })();
                              {
                                const $t29476_i12553 = (() => {
                                  {
                                    const $t1603_i5376_i12552 = Math.floor(x_i12551);
                                    return $t1603_i5376_i12552;
                                  }
                                })();
                                return (x_i12551 - $t29476_i12553);
                              }
                            }
                          }
                        }
                      })();
                      return ($t29604_i9753 * 4.);
                    }
                  })();
                  return Math.trunc($t29605_i9754);
                }
              })();
              return (2 + $t29606_i9755);
            }
          })();
          return draw_pulse_particle(ctx, s, t, $t29700, 0);
        }
      }
    }
  }
}
const $jp29701$apply$3813$clo = { _0: ($_, $clo) => $jp29701$apply$3813($clo) };

function $jp29703$apply$3814($clo) {
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
          const $t29700 = (() => {
            {
              const $t29606_i9763 = (() => {
                {
                  const $t29605_i9762 = (() => {
                    {
                      const $t29604_i9761 = (() => {
                        {
                          const $t29601_i9758 = (() => {
                            {
                              const $t29600_i9757 = s.x;
                              return ($t29600_i9757 + 4.);
                            }
                          })();
                          {
                            const $t29603_i9760 = (() => {
                              {
                                const $t29602_i9759 = s.y;
                                return ($t29602_i9759 + 4.);
                              }
                            })();
                            {
                              const x_i12560 = (() => {
                                {
                                  const $t29475_i12559 = (() => {
                                    {
                                      const $t29474_i12558 = (() => {
                                        {
                                          const $t29472_i12556 = ($t29601_i9758 * 12.9898);
                                          {
                                            const $t29473_i12557 = ($t29603_i9760 * 78.233);
                                            return ($t29472_i12556 + $t29473_i12557);
                                          }
                                        }
                                      })();
                                      return Math.sin($t29474_i12558);
                                    }
                                  })();
                                  return ($t29475_i12559 * 43758.5453);
                                }
                              })();
                              {
                                const $t29476_i12562 = (() => {
                                  {
                                    const $t1603_i5376_i12561 = Math.floor(x_i12560);
                                    return $t1603_i5376_i12561;
                                  }
                                })();
                                return (x_i12560 - $t29476_i12562);
                              }
                            }
                          }
                        }
                      })();
                      return ($t29604_i9761 * 4.);
                    }
                  })();
                  return Math.trunc($t29605_i9762);
                }
              })();
              return (2 + $t29606_i9763);
            }
          })();
          return draw_pulse_particle(ctx, s, t, $t29700, 0);
        }
      }
    }
  }
}
const $jp29703$apply$3814$clo = { _0: ($_, $clo) => $jp29703$apply$3814($clo) };

function $jp29837$apply$3817($clo) {
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
const $jp29837$apply$3817$clo = { _0: ($_, $clo) => $jp29837$apply$3817($clo) };

function $lam30111$apply$3838($clo, k) {
  {
    const $t30112 = (() => {
      return (k === "m");
    })();
    {
      const $t30113 = (k === "M");
      return ($t30112 || $t30113);
    }
  }
}
const $lam30111$apply$3838$clo = { _0: ($_, $clo, k) => $lam30111$apply$3838($clo, k) };

function $jp30169$apply$3840($clo) {
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
const $jp30169$apply$3840$clo = { _0: ($_, $clo) => $jp30169$apply$3840($clo) };

function $lam30180$apply$3841($clo, _) {
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
const $lam30180$apply$3841$clo = { _0: ($_, $clo, _) => $lam30180$apply$3841($clo, _) };

function $lam30193$apply$3842($clo, _) {
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
const $lam30193$apply$3842$clo = { _0: ($_, $clo, _) => $lam30193$apply$3842($clo, _) };

function go$apply$4100($clo, lst, acc) {
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
const go$apply$4100$clo = { _0: ($_, $clo, lst, acc) => go$apply$4100($clo, lst, acc) };

function go$apply$4327($clo, lst, acc) {
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
const go$apply$4327$clo = { _0: ($_, $clo, lst, acc) => go$apply$4327($clo, lst, acc) };

function go$apply$4747($clo, lst, acc) {
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
            const go_i10755 = { $: "$Clo_go$5254", _0: go$apply$5254 };
            {
              const $t274_i10756 = { $: "Nil" };
              return go$apply$5254(go_i10755, acc, $t274_i10756);
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
            const go_i10760 = { $: "$Clo_go$5254", _0: go$apply$5254 };
            {
              const $t274_i10761 = { $: "Nil" };
              return go$apply$5254(go_i10760, acc, $t274_i10761);
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
            const go_i10765 = { $: "$Clo_go$5256", _0: go$apply$5256 };
            {
              const $t274_i10766 = { $: "Nil" };
              return go$apply$5256(go_i10765, acc, $t274_i10766);
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
            const go_i10770 = { $: "$Clo_go$5256", _0: go$apply$5256 };
            {
              const $t274_i10771 = { $: "Nil" };
              return go$apply$5256(go_i10770, acc, $t274_i10771);
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
            const go_i10781 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t274_i10782 = { $: "Nil" };
              return go$apply$4761(go_i10781, acc, $t274_i10782);
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
            const go_i10786 = { $: "$Clo_go$4761", _0: go$apply$4761 };
            {
              const $t274_i10787 = { $: "Nil" };
              return go$apply$4761(go_i10786, acc, $t274_i10787);
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
            const go_i10791 = { $: "$Clo_go$4327", _0: go$apply$4327 };
            {
              const $t274_i10792 = { $: "Nil" };
              return go$apply$4327(go_i10791, acc, $t274_i10792);
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
            const $t567 = (() => {
              {
                const go_i10802 = { $: "$Clo_go$4757", _0: go$apply$4757 };
                {
                  const $t274_i10803 = { $: "Nil" };
                  return go$apply$4757(go_i10802, yes, $t274_i10803);
                }
              }
            })();
            {
              const $t568 = (() => {
                {
                  const go_i10799 = { $: "$Clo_go$4757", _0: go$apply$4757 };
                  {
                    const $t274_i10800 = { $: "Nil" };
                    return go$apply$4757(go_i10799, no, $t274_i10800);
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
            const $t567 = (() => {
              {
                const go_i10814 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                {
                  const $t274_i10815 = { $: "Nil" };
                  return go$apply$4761(go_i10814, yes, $t274_i10815);
                }
              }
            })();
            {
              const $t568 = (() => {
                {
                  const go_i10811 = { $: "$Clo_go$4761", _0: go$apply$4761 };
                  {
                    const $t274_i10812 = { $: "Nil" };
                    return go$apply$4761(go_i10811, no, $t274_i10812);
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
const go$apply$4778$clo = { _0: ($_, $clo, lst, yes, no) => go$apply$4778($clo, lst, yes, no) };

function $lam689$apply$4780($clo, y) {
  {
    const x = (() => {
      return $clo._1;
    })();
    return (y === x);
  }
}
const $lam689$apply$4780$clo = { _0: ($_, $clo, y) => $lam689$apply$4780($clo, y) };

function go$apply$4782($clo, lst, acc) {
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
            const go_i10822 = { $: "$Clo_go$4757", _0: go$apply$4757 };
            {
              const $t274_i10823 = { $: "Nil" };
              return go$apply$4757(go_i10822, acc, $t274_i10823);
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
const go$apply$4787$clo = { _0: ($_, $clo, lst, acc) => go$apply$4787($clo, lst, acc) };

function go$apply$4790($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10834 = { $: "$Clo_go$5259", _0: go$apply$5259 };
            {
              const $t274_i10835 = { $: "Nil" };
              return go$apply$5259(go_i10834, acc, $t274_i10835);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10831 = { $: "$Clo_go$5259", _0: go$apply$5259 };
                {
                  const $t274_i10832 = { $: "Nil" };
                  return go$apply$5259(go_i10831, acc, $t274_i10832);
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
const go$apply$4799$clo = { _0: ($_, $clo, lst, acc) => go$apply$4799($clo, lst, acc) };

function go$apply$4801($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10851 = { $: "$Clo_go$4805", _0: go$apply$4805 };
            {
              const $t274_i10852 = { $: "Nil" };
              return go$apply$4805(go_i10851, acc, $t274_i10852);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10848 = { $: "$Clo_go$4805", _0: go$apply$4805 };
                {
                  const $t274_i10849 = { $: "Nil" };
                  return go$apply$4805(go_i10848, acc, $t274_i10849);
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
            const go_i10856 = { $: "$Clo_go$4100", _0: go$apply$4100 };
            {
              const $t274_i10857 = { $: "Nil" };
              return go$apply$4100(go_i10856, acc, $t274_i10857);
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
            const go_i10865 = { $: "$Clo_go$5263", _0: go$apply$5263 };
            {
              const $t274_i10866 = { $: "Nil" };
              return go$apply$5263(go_i10865, acc, $t274_i10866);
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
const go$apply$4809$clo = { _0: ($_, $clo, lst, acc) => go$apply$4809($clo, lst, acc) };

function go$apply$4812($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10874 = { $: "$Clo_go$5263", _0: go$apply$5263 };
            {
              const $t274_i10875 = { $: "Nil" };
              return go$apply$5263(go_i10874, acc, $t274_i10875);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10871 = { $: "$Clo_go$5263", _0: go$apply$5263 };
                {
                  const $t274_i10872 = { $: "Nil" };
                  return go$apply$5263(go_i10871, acc, $t274_i10872);
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
            const go_i10882 = { $: "$Clo_go$5265", _0: go$apply$5265 };
            {
              const $t274_i10883 = { $: "Nil" };
              return go$apply$5265(go_i10882, acc, $t274_i10883);
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
            const go_i10887 = { $: "$Clo_go$5265", _0: go$apply$5265 };
            {
              const $t274_i10888 = { $: "Nil" };
              return go$apply$5265(go_i10887, acc, $t274_i10888);
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
const go$apply$4819$clo = { _0: ($_, $clo, lst, acc) => go$apply$4819($clo, lst, acc) };

function go$apply$4821($clo, lst, k, acc) {
  {
    const go = $clo;
    {
      const $t520 = (k <= 0);
      if ($t520 === true) {
        return (() => {
          {
            const go_i10895 = { $: "$Clo_go$4327", _0: go$apply$4327 };
            {
              const $t274_i10896 = { $: "Nil" };
              return go$apply$4327(go_i10895, acc, $t274_i10896);
            }
          }
        })();
      } else {
        return (() => {
          switch (lst.$) {
            case "Nil": {
              {
                const go_i10892 = { $: "$Clo_go$4327", _0: go$apply$4327 };
                {
                  const $t274_i10893 = { $: "Nil" };
                  return go$apply$4327(go_i10892, acc, $t274_i10893);
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
const go$apply$4823$clo = { _0: ($_, $clo, lst, acc) => go$apply$4823($clo, lst, acc) };

function go$apply$5254($clo, lst, acc) {
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
const go$apply$5254$clo = { _0: ($_, $clo, lst, acc) => go$apply$5254($clo, lst, acc) };

function go$apply$5256($clo, lst, acc) {
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
const go$apply$5256$clo = { _0: ($_, $clo, lst, acc) => go$apply$5256($clo, lst, acc) };

function go$apply$5259($clo, lst, acc) {
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
const go$apply$5259$clo = { _0: ($_, $clo, lst, acc) => go$apply$5259($clo, lst, acc) };

function go$apply$5261($clo, lst, acc) {
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
const go$apply$5261$clo = { _0: ($_, $clo, lst, acc) => go$apply$5261($clo, lst, acc) };

function go$apply$5263($clo, lst, acc) {
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
const go$apply$5263$clo = { _0: ($_, $clo, lst, acc) => go$apply$5263($clo, lst, acc) };

function go$apply$5265($clo, lst, acc) {
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
const go$apply$5265$clo = { _0: ($_, $clo, lst, acc) => go$apply$5265($clo, lst, acc) };

export { main };
main();
