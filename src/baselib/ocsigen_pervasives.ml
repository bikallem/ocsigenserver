(* Ocsigen
 * Copyright (C) 2005-2008 Vincent Balat, St�phane Glondu
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

exception Ocsigen_Internal_Error of string
exception Input_is_too_large
exception Ocsigen_Bad_Request
exception Ocsigen_Request_too_long

external id : 'a -> 'a = "%identity"

let (>>=) = Lwt.bind
let (>|=) = Lwt.(>|=)

let comp f g x = f (g x)
let uncurry2 f (x, y) = f x y

let map_option f = function
  | None -> None
  | Some v -> Some (f v)

let fst3 (a, _, _) = a
let snd3 (_, a, _) = a
let thd3 (_, _, a) = a

type yesnomaybe = Yes | No | Maybe
type ('a, 'b) leftright = Left of 'a | Right of 'b

let advert = "Page generated by OCaml with Ocsigen.
See http://ocsigen.org/ and http://caml.inria.fr/ for information"

(*****************************************************************************)

module List = struct

  include List

  let rec remove_first_if_any a = function
    |  [] -> []
    | b::l when a = b -> l
    | b::l -> b::(remove_first_if_any a l)

  let rec remove_first_if_any_q a = function
    |  [] -> []
    | b::l when a == b -> l
    | b::l -> b::(remove_first_if_any_q a l)

  let rec remove_first a = function
    |  [] -> raise Not_found
    | b::l when a = b -> l
    | b::l -> b::(remove_first a l)

  let rec remove_first_q a = function
    | [] -> raise Not_found
    | b::l when a == b -> l
    | b::l -> b::(remove_first_q a l)

  let rec remove_all a = function
    | [] -> []
    | b::l when a = b -> remove_all a l
    | b::l -> b::(remove_all a l)

  let rec remove_all_q a = function
    | [] -> []
    | b::l when a == b -> remove_all_q a l
    | b::l -> b::(remove_all_q a l)

  let rec remove_all_assoc a = function
    | [] -> []
    | (b, _)::l when a = b -> remove_all_assoc a l
    | b::l -> b::(remove_all_assoc a l)

  let rec remove_all_assoc_q a = function
    | [] -> []
    | (b,_)::l when a == b -> remove_all_assoc_q a l
    | b::l -> b::(remove_all_assoc_q a l)

  let rec last = function
    |  [] -> raise Not_found
    | [b] -> b
    | _::l -> last l

  let rec assoc_remove a = function
    | [] -> raise Not_found
    | (b, c)::l when a = b -> c, l
    | b::l -> let v, ll = assoc_remove a l in (v, b::ll)

  let rec is_prefix l1 l2 =
    match (l1, l2) with
    | [], _ -> true
    | a::ll1, b::ll2 when a=b -> is_prefix ll1 ll2
    | _ -> false

end

(*****************************************************************************)

(* circular lists *)
module Clist  : sig

  type 'a t
  type 'a node
  val make : 'a -> 'a node
  val create : unit -> 'a t
  val insert : 'a t -> 'a node -> unit
  val remove : 'a node -> unit
  val value : 'a node -> 'a
  val in_list : 'a node -> bool
  val is_empty : 'a t -> bool
  val iter : ('a -> unit) -> 'a t -> unit
  val fold_left : ('a -> 'b -> 'a) -> 'a -> 'b t -> 'a

end = struct

  type 'a node =
      { content : 'a option;
        mutable prev : 'a node;
        mutable next : 'a node }

  type 'a t = 'a node

  let make' c =
    let rec x = { content = c; prev = x; next = x } in
    x

  let make c = make' (Some c)

  let create () = make' None

  let insert p x =
    let n = p.next in
    p.next <- x;
    x.prev <- p;
    x.next <- n;
    n.prev <- x

  let remove x =
    let p = x.prev in
    let n = x.next in
    p.next <- n;
    n.prev <- p;
    x.next <- x;
    x.prev <- x

  let in_list x = x.next != x

  let is_empty set = set.next == set

  let value c =
    match c.content with
      | None -> failwith "Clist.value"
      | Some c -> c

  let rec iter f (node : 'a t) =
    match node.next.content with
      | Some c ->
          f c;
          iter f node.next
      | None -> ()

  let rec fold_left f a (node : 'a t) =
    match node.next.content with
      | Some c ->  fold_left f (f a c) node.next
      | None -> a

end

(*****************************************************************************)

module Int = struct

  module Table = Map.Make(struct
    type t = int
    let compare = compare
  end)

end

(*****************************************************************************)

module String = struct

  include String

  (* Returns a copy of the string from beg to endd,
     removing spaces at the beginning and at the end *)
  let remove_spaces s beg endd =
    let rec find_not_space s i step =
      if (i > endd) || (beg > i)
      then i
      else
	if s.[i] = ' '
	then find_not_space s (i+step) step
	else i
    in
    let first = find_not_space s beg 1 in
    let last = find_not_space s endd (-1) in
    if last >= first
    then String.sub s first (1+ last - first)
    else ""

  (* Cut a string to the next separator *)
  let basic_sep char s =
    try
      let seppos = String.index s char in
      ((String.sub s 0 seppos),
       (String.sub s (seppos+1)
          ((String.length s) - seppos - 1)))
    with Invalid_argument _ -> raise Not_found

  (* Cut a string to the next separator, removing spaces.
     Raises Not_found if the separator connot be found.
   *)
  let sep char s =
    let len = String.length s in
    let seppos = String.index s char in
    ((remove_spaces s 0 (seppos-1)),
     (remove_spaces s (seppos+1) (len-1)))

  (* splits a string, for ex azert,   sdfmlskdf,    dfdsfs *)
  let rec split ?(multisep=false) char s =
    let longueur = String.length s in
    let rec aux deb =
      if deb >= longueur
      then []
      else
	try
          let firstsep = String.index_from s deb char in
          if multisep && firstsep = deb then
            aux (deb + 1)
          else
            (remove_spaces s deb (firstsep-1))::
            (aux (firstsep+1))
	with Not_found -> [remove_spaces s deb (longueur-1)]
    in
    aux 0

  let may_append s1 ~sep = function
    | "" -> s1
    | s2 -> s1^sep^s2

  let may_concat s1 ~sep s2 = match s1, s2 with
  | _, "" -> s1
  | "", _ -> s2
  | _ -> String.concat sep [s1;s2]


  (* returns the index of the first difference between s1 and s2,
     starting from n and ending at last.
     returns (last + 1) if no difference is found.
   *)
  let rec first_diff s1 s2 n last =
    try
      if s1.[n] = s2.[n]
      then
	if n = last
	then last+1
	else first_diff s1 s2 (n+1) last
      else n
    with Invalid_argument _ -> n

  module Table = Map.Make(String)
  module Set = Set.Make(String)
  module Map = Map.Make(String)

  let make_cryptographic_safe =
    let rng = Cryptokit.Random.device_rng "/dev/urandom"
    and to_hex = Cryptokit.Hexa.encode () in
    fun () ->
      let random_part =
        let random_number = Cryptokit.Random.string rng 20 in
        Cryptokit.transform_string to_hex random_number
      and sequential_part =
        Printf.sprintf "%Lx" (Int64.bits_of_float (Unix.gettimeofday ())) in
      random_part ^ sequential_part

  (* The string is produced from the concatenation of two components:
     a 160-bit random sequence obtained from /dev/urandom, and a
     64-bit sequential component derived from the system clock.  The
     former is supposed to prevent session spoofing.  The assumption
     is that given the high cryptographic quality of /dev/urandom, it
     is impossible for an attacker to deduce the sequence of random
     numbers produced.  As for the latter component, it exists to
     prevent a theoretical (though infinitesimally unlikely) session
     ID collision if the server were to be restarted.  *)

end

(*****************************************************************************)

module Url = struct

  type t = string
  type uri = string
  type path = string list

  let make_absolute_url ~https ~host ~port uri =
    (if https
    then "https://"
    else "http://"
    )^
    host^
    (if (port = 80 && not https) || (https && port = 443)
    then ""
    else ":"^string_of_int port)^
    uri


  let remove_dotdot = (* removes "../" *)
    let rec aux = function
      | [] -> []
      | [""] as l -> l
(*    | ""::l -> aux l *) (* we do not remove "//" any more,
                             because of optional suffixes in Eliom *)
      | ".."::l -> aux l
      | a::l -> a::(aux l)
    in function
      | [] -> []
      | ""::l -> ""::(aux l)
      | l -> aux l

  let remove_end_slash s =
    try
      if s.[(String.length s) - 1] = '/'
      then String.sub s 0 ((String.length s) - 1)
      else s
    with Invalid_argument _ -> s


  let remove_internal_slash u =
    let rec aux = function
      | [] -> []
      | [a] -> [a]
      | ""::l -> aux l
      | a::l -> a::(aux l)
    in match u with
    | [] -> []
    | a::l -> a::(aux l)

  let change_empty_list = function
    | [] -> [""] (* It is not possible to register an empty URL *)
    | l -> l

  let rec add_end_slash_if_missing = function
    | [] -> [""]
    | [""] as a -> a
    | a::l -> a::(add_end_slash_if_missing l)

  let rec remove_slash_at_end = function
    | []
    | [""] -> []
    | a::l -> a::(remove_slash_at_end l)

  let remove_slash_at_beginning = function
    | [] -> []
    | [""] -> [""]
    | ""::l -> l
    | l -> l

  let rec recursively_remove_slash_at_beginning = function
    | [] -> []
    | [""] -> [""]
    | ""::l -> recursively_remove_slash_at_beginning l
    | l -> l

  let rec is_prefix_skip_end_slash l1 l2 =
    match (l1, l2) with
    | [""], _
    | [], _ -> true
    | a::ll1, b::ll2 when a=b -> is_prefix_skip_end_slash ll1 ll2
    | _ -> false

  (* Taken from Neturl version 1.1.2 *)
  let problem_re1 = Netstring_pcre.regexp "[ <>\"{}|\\\\^\\[\\]`]"

  let fixup_url_string1 =
    Netstring_pcre.global_substitute
      problem_re1
      (fun m s ->
	Printf.sprintf "%%%02x"
          (Char.code s.[Netstring_pcre.match_beginning m]))

  (* I add this fixup to handle %uxxxx sent by browsers.
     Translated to %xx%xx *)
  let problem_re2 = Netstring_pcre.regexp "\\%u(..)(..)"

  let fixup_url_string s =
    fixup_url_string1
      (Netstring_pcre.global_substitute
	 problem_re2
	 (fun m s ->
           String.concat "" ["%"; Netstring_pcre.matched_group m 1 s;
                             "%"; Netstring_pcre.matched_group m 2 s]
	 )
	 s)

  (*VVV This is in Netencoding but we have a problem with ~
        (not encoded by browsers). Here is a patch that does not encode '~': *)
  module MyUrl = struct

    let hex_digits =
      [| '0'; '1'; '2'; '3'; '4'; '5'; '6'; '7';
	 '8'; '9'; 'A'; 'B'; 'C'; 'D'; 'E'; 'F' |]

    let to_hex2 k =
      (* Converts k to a 2-digit hex string *)
      let s = String.create 2 in
      s.[0] <- hex_digits.( (k lsr 4) land 15 );
      s.[1] <- hex_digits.( k land 15 );
      s

    let url_encoding_re =
      Netstring_pcre.regexp "[^A-Za-z0-9~_.!*\\-]"

    let encode ?(plus = true) s =
      Netstring_pcre.global_substitute
	url_encoding_re
	(fun r _ ->
	  match Netstring_pcre.matched_string r s with
	  | " " when plus -> "+"
	  | x ->
              let k = Char.code(x.[0]) in
              "%" ^ to_hex2 k
	)
	s

  end

  let encode = MyUrl.encode
  let decode ?plus a = Netencoding.Url.decode ?plus a

  let make_encoded_parameters = Netencoding.Url.mk_url_encoded_parameters

  let string_of_url_path ~encode l =
    if encode
    then
      fixup_url_string (String.concat "/"
                          (List.map (*Netencoding.Url.encode*)
                             MyUrl.encode l))
    else String.concat "/" l (* BYXXX : check illicit characters *)


  let parse =

    (* We do not accept http://login:pwd@host:port (should we?). *)
    let url_re = Netstring_pcre.regexp "^([Hh][Tt][Tt][Pp][Ss]?)://([0-9a-zA-Z.-]+|\\[[0-9A-Fa-f:.]+\\])(:([0-9]+))?/([^\\?]*)(\\?(.*))?$" in
    let short_url_re = Netstring_pcre.regexp "^/([^\\?]*)(\\?(.*))?$" in
(*  let url_relax_re = Netstring_pcre.regexp "^[Hh][Tt][Tt][Pp][Ss]?://[^/]+" in
 *)
    fun url ->

      let match_re = Netstring_pcre.string_match url_re url 0 in

      let (https, host, port, pathstring, query) =
	match match_re with
	| None ->
            (match Netstring_pcre.string_match short_url_re url 0 with
            | None -> raise Ocsigen_Bad_Request
            | Some m ->
		let path =
                  fixup_url_string (Netstring_pcre.matched_group m 1 url)
		in
		let query =
                  try
                    Some (fixup_url_string (Netstring_pcre.matched_group m 3 url))
                  with Not_found -> None
		in
		(None, None, None, path, query))
	| Some m ->
            let path = fixup_url_string (Netstring_pcre.matched_group m 5 url) in
            let query =
              try Some (fixup_url_string (Netstring_pcre.matched_group m 7 url))
              with Not_found -> None
            in
            let https =
              try (match Netstring_pcre.matched_group m 1 url with
              | "http" -> Some false
              | "https" -> Some true
              | _ -> None)
              with Not_found -> None in
            let host =
              try Some (Netstring_pcre.matched_group m 2 url)
              with Not_found -> None in
            let port =
              try Some (int_of_string (Netstring_pcre.matched_group m 4 url))
              with Not_found -> None in
            (https, host, port, path, query)
      in

      (* Note that the fragment (string after #) is not sent by browsers *)

      let get_params =
	lazy begin
          let params_string = match query with None -> "" | Some s -> s in
          try
            Netencoding.Url.dest_url_encoded_parameters params_string
          with Failure _ -> raise Ocsigen_Bad_Request
	end
      in

      let path = List.map Netencoding.Url.decode (Neturl.split_path pathstring) in

      let path = remove_dotdot path (* and remove "//" *)
          (* here we remove .. from paths, as it is dangerous.
             But in some very particular cases, we may want them?
             I prefer forbid that. *)
      in
      let uri_string = match query with
      | None -> pathstring
      | Some s -> String.concat "?" [pathstring; s]
      in

      (https, host, port, uri_string, path, query, get_params)

end

(*****************************************************************************)

module Ip_address = struct

  type t =
    | IPv4 of int32
    | IPv6 of int64 * int64

  exception Invalid_ipaddress of string

  let parse s =
    let s = String.lowercase s in
    let n = String.length s in
    let is6 = String.contains s ':' in
    let failwith fmt = Printf.ksprintf (fun s -> raise (Invalid_ipaddress s)) fmt in

    let rec parse_hex i accu =
      match (if i < n then s.[i] else ':') with
      | '0'..'9' as c -> parse_hex (i+1) (16*accu+(int_of_char c)-48)
      | 'a'..'f' as c -> parse_hex (i+1) (16*accu+(int_of_char c)-87)
      | _ -> (i, accu)
    in
    let rec parse_dec i accu =
      match (if i < n then s.[i] else '.') with
      | '0'..'9' as c -> parse_dec (i+1) (10*accu+(int_of_char c)-48)
      | _ -> (i, accu)
    in
    let rec next_is_dec i =
      if i < n then
	match s.[i] with
        | ':' -> false
        | '.' -> true
        | _ -> next_is_dec (i+1)
      else false
    in
    let rec parse_component i accu nb =
      if i < n then
	if next_is_dec i then
          let (i1, a) = parse_dec i 0 in
          if i1 = i || (i1 < n && s.[i1] <> '.') then failwith "invalid dot notation in %s (1)" s;
          let (i2, b) = parse_dec (i1+1) 0 in
          if i2 = i1 then failwith "invalid dot notation in %s (2)" s;
          let component =
            if a < 0 || a > 255 || b < 0 || b > 255 then
              failwith "invalid dot notation in %s (3)" s
            else (a lsl 8) lor b
          in
          if i2 < n-1 && (s.[i2] = ':' || s.[i2] = '.') then
            parse_component (i2+1) (component::accu) (nb+1)
          else
            (i2, component::accu, nb+1)
	else if s.[i] = ':' then
          parse_component (i+1) ((-1)::accu) nb
	else
          let (i1, a) = parse_hex i 0 in
          if a < 0 || a > 0xffff then failwith "invalid colon notation in %s" s;
          if i1 = i then
            (i, accu, nb)
          else if i1 < n-1 && s.[i1] = ':' then
            parse_component (i1+1) (a::accu) (nb+1)
          else
            (i1, a::accu, nb+1)
      else
	(i, accu, nb)
    in

    let (i, addr_list, size_list) =
      if 1 < n && s.[0] = ':' && s.[1] = ':' then
	parse_component 2 [-1] 0
      else
	parse_component 0 [] 0
    in

    if size_list > 8 then failwith "too many components in %s" s;

    let maybe_mask =
      if i < n && s.[i] = '/' then
	let (i1, m) = parse_dec (i+1) 0 in
	if i1 = i+1 || i1 < n || m < 0 || m > (if is6 then 128 else 32) then
          failwith "invalid /n suffix in %s" s
	else
          Some m
      else if i < n then
	failwith "invalid suffix in %s (from index %i)" s i
      else
	None
    in

    if is6 then
      let (++) a b = Int64.logor (Int64.shift_left a 16) (Int64.of_int b) in
      let normalized =
	let rec aux_add n accu =
          if n = 0 then accu else aux_add (n-1) (0::accu)
	in
	let rec aux_rev accu = function
          | [] -> accu
          | (-1)::q -> aux_rev (aux_add (8-size_list) accu) q
          | a::q -> aux_rev (a::accu) q
	in
	aux_rev [] addr_list
      in
      let maybe_mask = match maybe_mask with
      | Some n when n > 64 ->
          Some (IPv6 (Int64.minus_one, Int64.shift_left Int64.minus_one (128-n)))
      | Some n ->
          Some (IPv6 (Int64.shift_left Int64.minus_one (64-n), Int64.zero))
      | None -> None
      in
      match normalized with
      | [a; b; c; d; e; f; g; h] ->
          IPv6 (Int64.zero ++ a ++ b ++ c ++ d,
                Int64.zero ++ e ++ f ++ g ++ h), maybe_mask
      | _ -> failwith "invalid IPv6 address: %s (%d components)" s (List.length normalized)
    else
      let (++) a b = Int32.logor (Int32.shift_left a 16) (Int32.of_int b) in
      let maybe_mask = match maybe_mask with
      | Some n ->
          Some (IPv4 (Int32.shift_left Int32.minus_one (32-n)))
      | None -> None
      in
      match addr_list with
      | [b; a] ->
          IPv4 (Int32.zero ++ a ++ b), maybe_mask
      | _ -> failwith "invalid IPv4 address: %s" s


  let match_ip (base, mask) ip =
    match ip,  base, mask with
    | IPv4 a, IPv4 b, Some (IPv4 m) -> Int32.logand a m = Int32.logand b m
    | IPv4 a, IPv4 b, None -> a = b
    | IPv6 (a1,a2), IPv6 (b1,b2), Some (IPv6 (m1,m2)) ->
        Int64.logand a1 m1 = Int64.logand b1 m1 &&
        Int64.logand a2 m2 = Int64.logand b2 m2
    | IPv6 (a1,a2), IPv6 (b1,b2), None -> a1 = b1 && a2 = b2
    | IPv6 (a1,a2), IPv4 b, c
      when a1 = 0L && Int64.logand a2 0xffffffff00000000L = 0xffff00000000L ->
        (* might be insecure, cf
           http://tools.ietf.org/internet-drafts/draft-itojun-v6ops-v4mapped-harmful-02.txt *)
        let a = Int64.to_int32 a2 in
        begin match c with
        | Some (IPv4 m) -> Int32.logand a m = Int32.logand b m
        | Some (IPv6 _) -> invalid_arg "match_ip"
        | None -> a = b
        end
    | _ -> false

  let network_of_ip ~ip ~mask = match ip, mask with
  | IPv4 a, IPv4 mask4 -> IPv4 (Int32.logand a mask4)
  | IPv6 (a, b), IPv6 (mask61, mask62) -> IPv6 (Int64.logand a mask61, Int64.logand b mask62)
  | _ -> invalid_arg "Ip_address.network_of_ip"

  exception No_such_host

  let inet6_addr_loopback =
    fst (parse (Unix.string_of_inet_addr Unix.inet6_addr_loopback))

  let get_inet_addr host =
    let rec aux = function
      | [] -> Lwt.fail No_such_host
      | {Unix.ai_addr=Unix.ADDR_INET (inet_addr, _)}::_ -> Lwt.return inet_addr
      | _::l -> aux l
    in
    Lwt.bind
      (Lwt_unix.getaddrinfo host "" [])
      aux

  let getnameinfo ia p =
    try
      Lwt_unix.getnameinfo (Unix.ADDR_INET (ia, p)) [Unix.NI_NAMEREQD] >>= fun r ->
	Lwt.return r.Unix.ni_hostname
    with
    | Not_found ->
	let hs = Unix.string_of_inet_addr ia in
	Lwt.return
          (if String.length hs > 7 && String.sub hs 0 7 = "::ffff:"
          then String.sub hs 7 (String.length hs - 7)
          else if String.contains hs ':'
          then "["^hs^"]"
          else hs)

end

(************************************************************************)

module Filename = struct

  include Filename

  let basename f =
    let n = String.length f in
    let i = try String.rindex f '\\' + 1 with Not_found -> 0 in
    let j = try String.rindex f '/' + 1 with Not_found -> 0 in
    let k = max i j in
    if k < n then
      String.sub f k (n-k)
    else
      "none"

  let extension_no_directory filename =
    try
      let pos = String.rindex filename '.' in
      String.sub filename (pos+1) ((String.length filename) - pos - 1)
    with Not_found ->
      raise Not_found

  let extension filename =
    try
      let pos = String.rindex filename '.'
      and slash =
	try String.rindex filename '/'
	with Not_found -> -1
      in
      if pos > slash then
	String.sub filename (pos+1) ((String.length filename) - pos - 1)
      else (* Dot before a directory separator *)
	raise Not_found
    with Not_found -> (* No dot in filename *)
      raise Not_found

end

(*****************************************************************************)

module Printexc = struct

  include Printexc

  let exc_printer = ref (fun _ e -> Printexc.to_string e)

  let rec to_string e = !exc_printer to_string e

  let register_exn_printer p =
    let printer =
      let old = !exc_printer in
      (fun f_rec s ->
        try p f_rec s
        with e -> old f_rec s) in
    exc_printer := printer

end

(*****************************************************************************)

let debug = prerr_endline