(**
   Kawa : a small object language inspired by Java
 *)

(* Declared types (used by attributes, variables, args and return type in methods. *)
type typ =
  | TVoid
  | TInt
  | TBool
  | TClass of string

let typ_to_string = function
  | TVoid    -> "void"
  | TInt     -> "int"
  | TBool    -> "bool"
  | TClass c -> c

type unop  = Opp | Not
type binop = Add | Sub | Mul | Div | Mod
           | Le  | Lt  | Ge | Gt | Eq  | Neq
           | And | Or

(* Expressions *)
type expr =
  (* Arithmetic *)
  | Int      of int
  | Bool     of bool
  | Null
  | Unop     of unop * expr
  | Binop    of binop * expr * expr
  | TerCond  of expr * expr * expr
  (* Get the content of a var or an attributte *)
  | Get      of mem_access
  (* Current object *)
  | This
  (* Create a new object *)
  | New      of string
  | NewCstr  of string * expr list
  (* Call a method *)
  | MethCall of expr * string * expr list

(* Memory access : either a variable or an attribute *)
and mem_access =
  | Var   of string
  | Field of expr (* object *) * string (* attribute's name *)

(* Instructions *)
type instr =
  (* Print a boolean or an int *)
  | Print  of expr
  (* Set the content in a variable or an attribute *)
  | Set    of mem_access * expr
  (* Condition control *)
  | Cond   of cond
  (* Loops *)
  (* | For    of expr * expr * expr * seq *)
  | While  of expr * seq
  | DoWhile of seq * instr
  (* End of a method *)
  | Return of expr
  (* Expression *)
  | Expr   of expr
and cond =
  | If        of expr * seq
  | If_Else   of expr * seq * cond
  | Else      of seq
and seq = instr list

(* Method's definition

   Syntax : method <return type> <name> (<params>) { ... }

   Method's body is similar to the main's body *)
type method_def = {
    method_name: string;
    code: seq;
    params: (string * typ) list;
    locals: (string * typ) list;
    return: typ;
  }
        
(* Class's definition

   Syntax : class <class name> { ... }
       or : class <class name> extends <mother class name> { ... }

   The class's constructor is a void-typed method called "constructor" *)
type class_def = {
    class_name: string;
    attributes: (string * typ) list;
    methods: method_def list;
    parent: string option;
  }

(* Program : global variables, classes, and an instruction sequence (the main) *)
type program = {
    classes: class_def list;
    globals: (string * typ) list;
    main: seq;
  }
