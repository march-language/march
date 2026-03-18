type t
(** Opaque terminal handle. *)

type scope_entry = {
  name     : string;
  type_str : string;
  val_str  : string;
}

type pane_content = {
  history       : Notty.I.t list;
  (** Rendered transcript lines, oldest first. *)
  input_line    : Notty.I.t;
  (** Current highlighted input (without prompt). *)
  prompt        : string;
  (** e.g. "march(3)> " *)
  scope         : scope_entry list;
  (** User-defined bindings for right pane. *)
  result_latest : (string * string) option;
  (** Most recent v: (type_str, val_str). *)
  status        : string;
  (** Status bar text. *)
}

val create : unit -> t
(** Open the notty terminal in raw mode. *)

val close : t -> unit
(** Restore terminal state. *)

val render : t -> pane_content -> unit
(** Compose and display a full screen frame. *)

val next_event : t -> [ `Key of Notty.Unescape.key | `Resize of int * int | `End ]
(** Block until next terminal event. Returns [`Key], [`Resize], or [`End] (EOF/signal). *)

val size : t -> int * int
(** Current terminal (width, height). *)
