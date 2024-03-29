%{

  open Lexing
  open Kawa

  (* Manage the setting when initialiasing a variable *)
  let init_and_setting_vars (var : ((string * typ) list * instr) list) : (string, typ) Hashtbl.t * seq =
    let rec var_set (l : seq) : seq =
      match l with
      | [] -> []
      | s :: l -> 
        begin
          (* get rid of non-initialisation, so Null : it will be set to null anyway by the program before starting *)
          match s with
          | Set _ -> s :: var_set l
          | _ -> var_set l
        end
    in
    let set = var_set @@ List.map snd var in
    let var = List.flatten @@ List.map fst var in
    let var_hash = Hashtbl.create 5 in
    let () = List.iter (fun (x, t) -> Hashtbl.replace var_hash x t) var in
    var_hash, set
%}

%token <int> N
%token <float> F
%token <char> C
%token <string> S
%token TRUE FALSE
%token NULL

%token INT FLOAT CHAR STRING BOOL VOID
%token <string> IDENT

%token LPAR RPAR BEGIN END SEMI
/* %token LBRA RBRA */

%token PLUS MINUS TIMES SLASH MOD
%token PLUS_SET MINUS_SET TIMES_SET SLASH_SET

%token NOT AND OR
%token LE LT GE GT EQ NEQ

%token SET

%token INTERO TWO_PT IF ELSE
%token DO WHILE FOR

%token NEW CLASS EXTENDS
%token THIS DOT
%token COMMA RETURN

%token MAIN
%token PRINT PRINTLN INPUT ASSERT
%token INSTANCEOF
%token EOF


/* Priority from Java

   Source :
   [https://pages.cs.wisc.edu/~willb/cs302/java-operator-precedence.pdf]

   Even if some are useless, I choose to put them just in case
*/
%right INTERO TWO_PT

%left OR
%left AND
%left EQ NEQ
%left LT LE GT GE INSTANCEOF
%nonassoc NOT

%left PLUS MINUS 
%left TIMES SLASH MOD

%left DOT


%start program
%type <Kawa.program> program

%%

/* The idea of splitting program and class_def like this came from a friend of mine : I thank them */
program:
| prog=program_variables
  { 
    let vars, cls, main = prog in
    let vars, set = init_and_setting_vars vars in

    (* Better than a list *)
    let cls_hash = Hashtbl.create 5 in
    let () = List.iter (fun c -> Hashtbl.replace cls_hash c.class_name c) cls in
    (* Flatten all attributes with inheritance *)
    let rec inheritance (c_name : string) 
                        (c : class_def) : unit =
      (* Find the parent *)
      match c.parent with
      | Some p ->
        begin
          (* Get the parent's class *)
          let p_cls = Interpreter.get_class cls_hash p in
          (* We keep the 'youngest' attribute so if it's already in it, we do not
            want to erase it (since we read from child to parent)*)
          let add_but_not_erase (x : string) 
                                (t : typ) : unit =
            match Hashtbl.find_opt c.attributes x with
            | None -> Hashtbl.replace c.attributes x t
            | Some _ -> ()
          in
          let () = Hashtbl.iter add_but_not_erase p_cls.attributes in
          inheritance p p_cls
        end
      | None -> ()
    in
    let () = Hashtbl.iter inheritance cls_hash in
    { classes = cls_hash ; globals = vars ; main = set @ main } 
  }
;
/* To get rid of 'var' keyword */
program_variables:
| var=var_decl prog=program_variables
  { 
    let vars, cls, main = prog in
    var :: vars, cls, main
  }
| cls=program_classes
  { [], fst cls, snd cls }
;
program_classes:
| c=class_def cls=program_classes
  { c :: (fst cls), snd cls }
| MAIN s=seq EOF { [], s }
;
seq:
| BEGIN body=list(instr_semi) END { body }
;


class_def:
| CLASS i=IDENT pt=option(EXTENDS p=IDENT { p }) BEGIN cls=class_def_attributes
  { 
    let attr_hash = Hashtbl.create 5 in
    let () = List.iter (fun (x, t) -> Hashtbl.replace attr_hash x t) (fst cls) in
    let meth_hash = Hashtbl.create 5 in
    (* Overloading don't allow same method name with same parameters types *)
    let check_if_double (m : method_def) : unit =
      match Hashtbl.find_opt meth_hash m.method_name with
      | None -> Hashtbl.replace meth_hash m.method_name m
      | Some _ -> raise (Interpreter.Error ("overloading error: there is at least twice the same method '" ^ m.method_name ^ "'' with the same parameters' type in the class '" ^ i ^ "'."))
    in
    let () = List.iter check_if_double (snd cls) in
    { class_name = i ; attributes = attr_hash ; methods = meth_hash ; parent = pt }  
  } 
;
/* To get rid of 'attribute' and 'method' keywords*/
class_def_attributes:
| attr=attr_decl cls=class_def_attributes
  { attr @ (fst cls), snd cls }
| meths=class_def_constructor
  { [], meths }
;
class_def_constructor:
| c=constructor_def meths=class_def_constructor
  { c :: meths }
| meths=class_def_methods
  { meths }
;
class_def_methods:
| m=method_def meths=class_def_methods
  { m :: meths }
| END
  { [] }
;



var_decl:
| t=typ i=IDENT SET e=expr SEMI
  { [ (i, t) ], Set(Var(i), S_Set, e) }
| t=typ l=separated_nonempty_list(COMMA, i=IDENT { i }) SEMI 
  { List.map (fun i -> (i, t)) l, Expr(Null) }
;
attr_decl:
| t=typ l=separated_nonempty_list(COMMA, i=IDENT { i }) SEMI 
  { List.map (fun i -> (i, t)) l }
;



typ:
| INT { TInt }
| FLOAT { TFloat }
| STRING { TString }
| CHAR { TChar }
| BOOL { TBool }
| i=IDENT { TClass i }
| VOID { TVoid }
;


constructor_def:
| i=IDENT LPAR arg=separated_list(COMMA, t=typ i=IDENT { (i, t) }) RPAR BEGIN vars=constructor_variables END
  {
    let var, body = vars in
    let vars, set = init_and_setting_vars var in
    let m_name = Interpreter.method_name_type i @@ List.map snd arg in
    { method_name = m_name ; code = set @ body ; params = arg ; locals = vars ; return = TVoid } 
  }
;
/* To get rid of 'var' keyword */
constructor_variables:
| var=var_decl vars=constructor_variables
  { (var :: (fst vars)), (snd vars) }
| body=list(instr_semi)
  { [], body }
method_def:
| t=typ i=IDENT LPAR arg=separated_list(COMMA, t=typ i=IDENT { (i, t) }) RPAR BEGIN vars=method_variables END
  { 
    let var, body = vars in
    let vars, set = init_and_setting_vars var in
    let m_name = Interpreter.method_name_type i (List.map snd arg) in
    { method_name = m_name ; code = set @ body ; params = arg ; locals = vars ; return = t } 
  }
;
/* To get rid of 'var' keyword */
method_variables:
| var=var_decl vars=method_variables
  { (var :: (fst vars)), (snd vars) }
| body=list(instr_semi)
  { [], body }



expr:
| n=N { Int(n) }
| INT LPAR e=expr RPAR { IntCast(e) }
/*| LPAR INT RPAR e=expr { IntCast(e) }*/
| f=F { Float(f) }
| FLOAT LPAR e=expr RPAR { FloatCast(e) }
/*| LPAR FLOAT RPAR e=expr { FloatCast(e) }*/
| c=C { Char(c) }
| s=S { String(s) }
| STRING LPAR e=expr RPAR { StringCast(e) }
/*| LPAR STRING RPAR e=expr { StringCast(e) }*/

| TRUE { Bool(true) }
| FALSE { Bool(false) }

| NULL { Null }

| u=uop e=expr { Unop(u, e) }
| e1=expr b=bop e2=expr { Binop(b, e1, e2) }

| t=expr INTERO e1=expr TWO_PT e2=expr { TerCond(t, e1, e2) }

| e=expr INSTANCEOF t=typ { InstanceOf(e, t) }

| m=mem { Get(m) }

| THIS { This }

| LPAR e=expr RPAR { e }

| NEW i=IDENT { New i }
| NEW i=IDENT LPAR arg=separated_list(COMMA, expr) RPAR 
  { NewCstr(i, arg) }

| e=expr DOT i=IDENT LPAR arg=separated_list(COMMA, expr) RPAR
  { MethCall(e, i, arg) }
;
mem:
| i=IDENT { Var i }
| e=expr DOT i=IDENT { Field(e, i) }
;



instr:
| PRINT LPAR e=expr RPAR { Print e }
| PRINTLN LPAR e=expr RPAR { Println e }
| INPUT LPAR e=expr RPAR { Input(None, e) }
| INPUT LPAR s=expr COMMA e=expr RPAR { Input(Some s, e) }
| ASSERT LPAR e=expr RPAR { Assert e }

| m=mem s=set e=expr { Set(m, s, e) }

| DO s=seq WHILE LPAR e=expr RPAR { DoWhile(s, While(e, s)) }

| RETURN e=option(expr) { Return e }

| e=expr { Expr e }
;
instr_semi:
| c=cond { Cond(c) }

| FOR LPAR s=instr SEMI c=expr SEMI incr=instr RPAR seq=seq
  { For(None, s, c, incr, seq) }
| FOR LPAR t=typ i=IDENT SET e=expr SEMI c=expr SEMI incr=instr RPAR seq=seq
  { For(Some t, Set(Var(i), S_Set, e), c, incr, seq) }
| WHILE LPAR e=expr RPAR s=seq { While(e, s) }

| i=instr SEMI { i }
cond:
| IF LPAR e=expr RPAR s=seq { If(e, s) }
| IF LPAR e=expr RPAR s1=seq ELSE s2=seq { If_Else(e, s1, Else(s2)) }
| IF LPAR e=expr RPAR s=seq ELSE c=cond { If_Else(e, s, c) }
;



%inline bop :
| PLUS  { Add }
| MINUS { Sub }
| TIMES { Mul }
| SLASH { Div }
| MOD   { Mod }

| LE    { Le  }
| LT    { Lt  }
| GE    { Ge  }
| GT    { Gt  }
| EQ    { Eq  }
| NEQ   { Neq }

| AND   { And }
| OR    { Or  }
;
%inline uop :
| MINUS { Opp }

| NOT     { Not }
;

%inline set:
| SET       { S_Set }
| PLUS_SET  { S_Add }
| MINUS_SET { S_Sub }
| TIMES_SET { S_Mul }
| SLASH_SET { S_Div }