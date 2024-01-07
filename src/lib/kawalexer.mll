{

  open Lexing
  open Kawaparser

  exception Error of string

  let keyword_or_ident =
  let h = Hashtbl.create 30 in
  let () = List.iter (fun (s, k) -> Hashtbl.add h s k)
    [ 
      "true",       TRUE ;
      "false",      FALSE ;

      "null",       NULL ;

      "int",        INT ;
      "float",      FLOAT ;
      "char",       CHAR ;
      "string",     STRING ;
      "bool",       BOOL ;
      "void",       VOID ;

      "if",         IF ;
      "else",       ELSE ;

      "do",         DO ;
      "while",      WHILE ;
      "for",        FOR ;

      "new",        NEW ;
      "class",      CLASS ;
      "extends",    EXTENDS ;

      "this",       THIS ;

      "return",     RETURN ;

      "main",       MAIN ;
      "print",      PRINT ;
      "input",      INPUT ;
      "assert",     ASSERT ;
      "instanceof", INSTANCEOF ;
    ]
  in
  fun s ->
    match Hashtbl.find_opt h s with
    | Some k -> k
    | None -> IDENT(s)
}

let digit = ['0'-'9']
let decimals = '.' digit+

let integers = ( ['1'-'9'] digit+ ) | digit 

let exponent = ['e' 'E'] '-'? integers
let floats = decimals | ( integers '.' ) | ( integers decimals ) | ( integers decimals? exponent )

let chr = ([^ '\''] | ([^ '\''] '\\' '\'' [^ '\'']) )
let str = ([^ '\"'] | ([^ '\"'] '\\' '\"' [^ '\"']) )*

(* Like Java *)
let ident = (['a'-'z' 'A'-'Z'] | '_' ['a'-'z' 'A'-'Z']) (['a'-'z' 'A'-'Z'] | '_' | digit)*
  
rule token = parse
  | ['\n']           { new_line lexbuf; token lexbuf }
  | [' ' '\t' '\r']+ { token lexbuf }

  | "//" [^ '\n']* '\n' { new_line lexbuf; token lexbuf }
  | "/*"                 { comment lexbuf; token lexbuf }

  | integers as n        { N(int_of_string n) }
  | floats as f          { F(Float.of_string f) }
  | '\"' (str as s) '\"' { S(s) }
  | '\'' (chr as c) '\'' { C(String.get c 0)}
  | ident as id          { keyword_or_ident id }

  | "("   { LPAR }
  | ")"   { RPAR }
  | "["   { LBRA }
  | "]"   { RBRA }
  | "{"   { BEGIN }
  | "}"   { END }
  | ";"   { SEMI }

  | "+"   { PLUS }
  | "-"   { MINUS }
  | "*"   { TIMES }
  | "/"   { SLASH }
  | "%"   { MOD }

  | "!"   { NOT }
  | "&&"  { AND }
  | "||"  { OR  }

  | "<="  { LE }
  | "<"   { LT }
  | ">="  { GE }
  | ">"   { GT }
  | "=="  { EQ }
  | "!="  { NEQ }

  | "="   { SET }
  | "+="  { PLUS_SET }
  | "-="  { MINUS_SET }
  | "*="  { TIMES_SET }
  | "/="  { SLASH_SET }

  | "?"   { INTERO }
  | ":"   { TWO_PT }
  
  | "."   { DOT }
  | ","   { COMMA }

  | _   { raise (Error ("unknown character : " ^ lexeme lexbuf)) }
  | eof { EOF }

and comment = parse
  | "*/" { () }
  | _    { comment lexbuf }
  | eof  { raise (Error "unterminated comment") }