open Kawa

type value =
  | VInt  of int
  | VFloat of float
  | VBool of bool
  | VObj  of obj
  | VNull
and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

exception Error of string
exception Return of value

let rec string_of_obj o =
  Printf.sprintf "Object<%s>(%s)" o.cls (Hashtbl.fold 
    (fun k v acc -> 
      acc ^ (if acc = "" then "" else "; ") ^ (Printf.sprintf "%s = %s" k 
        (
          match v with
          | VInt n -> string_of_int n
          | VFloat f -> Printf.sprintf "%F" f
          | VBool b -> if b then "true" else "false"
          | VObj o' -> string_of_obj o'
          | VNull -> "null"
        )
      ) 
    ) 
  o.fields "")

(* Get the value of [m] in the local_env then in the global_env

  We also give eval because it is out of its definition
  We also give f to use mem_acces in different usage (get the value vs assignment
      which is a quite similar code !)
 *)
let mem_acces m global_env local_env eval f =
  match m with
  | Var s ->
    begin 
      (* Check if the variable is in the local environment *)
      match Hashtbl.find_opt local_env s with
      | Some v -> f s local_env v
      | None ->
        begin 
          (* Check if the variable is in the global environment *)
          match Hashtbl.find_opt global_env s with
          | Some v -> f s global_env v
          | None -> raise (Error ("unbound value error: '" ^ s ^ "' is not declared in the scope."))
        end
    end
  | Field (e, s) ->
    begin
      (* Check if it's an object *)
      match eval e with
      | VObj o -> 
        begin
          (* Check if the field exists *)
          match Hashtbl.find_opt o.fields s with
          | Some v -> f s o.fields v
          | None -> raise (Error ("unbound value error: can't acces the field '" ^ s 
                                     ^ "' in the object of class '" ^ o.cls ^ "'."))
        end
      | _ -> failwith "Impossible : typechecker's work"
    end

(* Execute the main of [p] *)
let exec_prog p =
  let global_env = Hashtbl.create 16 in
  List.iter (fun (x, _) -> Hashtbl.replace global_env x VNull) p.globals;

  (* Execute the method [f args] in the object [this] *)
  let rec exec_meth f this args =
    (* Use an @ because i'm the only one who is allowed to do it (privelege) *)
    Hashtbl.replace args "@This" (VObj this) ;
    (* Add local variables *)
    List.iter (fun (x, _) -> Hashtbl.replace args x VNull) f.locals ;
    (* Execute method *)
    try
      exec_seq f.code args ;
      VNull
    (* Get the result if there is a return *)
    with Return e ->
      e

  (* Execute a seq [s] with the local environment [local_env] *)
  and exec_seq s local_env =
    (* Evaluate an expression [e] with the unary operator [op] *)
    let rec eval_unop op e =
      match op with
      | Opp ->
        begin
          match eval e with
          | VInt n -> VInt (-n)
          | VFloat f -> VFloat (-.f)
          | _ -> failwith "Impossible : typechecker's work"
        end
      | Not ->
        begin
          match eval e with
          | VBool b -> VBool (not b)
          | _ -> failwith "Impossible : typechecker's work"
        end

    (* Evaluate two expressions [e1] and [e2] with the binary operator [op] *)
    and eval_binop op e1 e2 =
      let bool_to_bool op =
        match eval e1, eval e2 with
        | VBool b1, VBool b2 -> VBool (op b1 b2)
        | _ -> failwith "Impossible : typechecker's work"
      in
      (* Manage the int and float conversion *)
      let num_to_num op_int op_float =
        match eval e1, eval e2 with
        | VInt n1, VInt n2 -> VInt (op_int n1 n2)
        | VFloat f, VInt n -> VFloat (op_float f (float n))
        | VInt n, VFloat f -> VFloat (op_float (float n) f)
        | VFloat f1, VFloat f2 -> VFloat (op_float f1 f2)
        | _ -> failwith "Impossible : typechecker's work"
      in
      (* Manage the int and float conversion 

        Because of type inference there is two operator even 
          it's the same one for both..... 
      *)
      let compare op_int op_float =
        match eval e1, eval e2 with
        | VInt n1, VInt n2 -> VBool (op_int n1 n2)
        | VFloat f, VInt n -> VBool (op_float f (float n))
        | VInt n, VFloat f -> VBool (op_float (float n) f)
        | VFloat f1, VFloat f2 -> VBool (op_float f1 f2)
        | _ -> failwith "Impossible : typechecker's work"
      in
      match op with
      | Add -> num_to_num (+) (+.)
      | Sub -> num_to_num (-) (-.)
      | Mul -> num_to_num ( * ) ( *. )
      | Div -> num_to_num (/) (/.)
      | Mod ->
        begin
          match eval e1, eval e2 with
          | VInt n1, VInt n2 -> VInt (n1 mod n2)
          | _ -> failwith "Impossible : typechecker's work"
        end
      | Le -> compare (<=) (<=)
      | Lt -> compare (<) (<)
      | Ge -> compare (>=) (>=)
      | Gt -> compare (>) (>)
      | Eq ->
        begin
          match eval e1, eval e2 with
          | VBool x, VBool y -> VBool (x = y)
          (* Two objects are equal if and only if they are physically the same object 
             And we have "(==) => (=)", so we have '&&' *)
          | VObj o1, VObj o2 -> VBool (o1 == o2 && o1 = o2)
          | VNull, VNull -> VBool(true)
          (* For integers and floats *)
          | _ -> compare (=) (=)
        end
      | Neq ->
        begin
          match eval e1, eval e2 with
          | VBool x, VBool y -> VBool (x <> y)
          (* Two objects are equal if and only if they are physically the same object 
             And we have "(==) => (=)", so we have '&&' *)
          | VObj o1, VObj o2 -> VBool (o1 != o2 && o1 <> o2)
          | VNull, VNull -> VBool(false)
          (* For integers and floats *)
          | _ -> compare (<>) (<>)
        end
      | And -> bool_to_bool (&&)
      | Or ->  bool_to_bool (||)

    (* Evaluate the call of the [o]'s method [m_name arg]*)
    and eval_call o m_name arg =
      (* Check if the class exists *)
      match List.find_opt (fun cl -> cl.class_name = o.cls ) p.classes with
      | Some c ->
        begin
          (* Check if the method in the class exists *)
          match List.find_opt (fun m -> m.method_name = m_name ) c.methods with
          | Some m ->
            let args = Hashtbl.create 5 in
            (* For readability *)
            let assignment t e var_name =
              match t, eval e with
              | TInt, VFloat f -> Hashtbl.replace args var_name (VInt (int_of_float f))
              | TFloat, VInt n -> Hashtbl.replace args var_name (VFloat (float n))
              | _ -> Hashtbl.replace args var_name (eval e)
            in
            (* Add all the parameters in the local environment *)
            List.iter2 (fun e (x, t) -> assignment t e x ) arg m.params ;
            (* Start the method call *)
            exec_meth m o args
          | None -> raise (Error ("unbound value error: can't acces the method '" ^ m_name 
                           ^ "' in the object of class '" ^ o.cls ^ "'."))
        end
      | None -> raise (Error ("unbound value error: '" ^ o.cls ^ "' class is not declared in the program."))

    (* Evaluate an expression [e] *)
    and eval e =
      match e with
      | Int n -> VInt n
      | Float f -> VFloat f
      | Bool b -> VBool b
      | Null -> VNull
      | Unop (op, e) -> eval_unop op e
      | Binop (op, e1, e2) -> eval_binop op e1 e2
      | TerCond (t, e1, e2) ->
        begin
          match eval t with
          | VBool b ->
            if b then
              eval e1
            else
              eval e2
          | _ -> failwith "Impossible : typechecker's work"
        end
      | Get m -> mem_acces m global_env local_env eval (fun _ _ x -> x)
      | This ->
        begin 
          (* Check if the variable is in the local environment *)
          match Hashtbl.find_opt local_env "@This" with
          | Some v -> v
          | None -> raise (Error "unbound value error: can't access to 'this'.\nHint : are you inside a class ?")
        end
      | New s ->
        (* Create a new object *)
        let o = { cls = s ; fields = Hashtbl.create 5 } in
        begin
          (* Check if the class exists *)
          match List.find_opt (fun cl -> cl.class_name = s ) p.classes with
          | Some c ->
            (* Set up all the attributes to VNull *)
            List.iter (fun (x, _) -> Hashtbl.replace o.fields x VNull ) c.attributes ;
            VObj o
          | None -> raise (Error ("unbound value error: '" ^ s ^ "' class is not declared in the program."))
        end
      | NewCstr (s, el) ->
        (* Create a new object *)
        let VObj(o) = eval (New s) in
        (* Call the constructor *)
        let _ = eval_call o s el in
        VObj o
      | MethCall (e, s, el) ->
        begin
          match eval e with
          | VObj o -> eval_call o s el
          | _ -> failwith "Impossible : typechecker's work"
        end
    
    in
    (* Execute an instruction [i] *)
    let rec exec i = 
      match i with
      | Print e -> 
        begin
          match eval e with
          | VInt n -> Printf.printf "%d\n" n
          | VFloat f -> Printf.printf "%F\n" f 
          | VBool b -> Printf.printf "%s\n" (if b then "true" else "false")
          | VObj o -> Printf.printf "%s\n" (string_of_obj o) 
          | VNull -> Printf.printf "null\n"
        end
      | Assert e ->
        begin
          match eval e with
          | VBool b ->
            if not b then
              raise (Error "AssertionError")
          | _ -> failwith "Impossible : typechecker's work"
        end
      | Set (m, s, e) ->
        begin
          (* For readability *)
          let assignment new_value var_name hash_tab old_value =
            match old_value, new_value with
            (* type conversion, then assignment *)
            | VInt _, VFloat f -> Hashtbl.replace hash_tab var_name (VInt (int_of_float f))
            | VFloat _, VInt n -> Hashtbl.replace hash_tab var_name (VFloat (float n))
            (* direct assignment *)
            | _ -> Hashtbl.replace hash_tab var_name new_value
          in
          let op_then_set op =
            let value_to_expr v =
              match v with
              | VInt n -> Int n
              | VFloat f -> Float f
              (* We are talking about arithmetic so... *)
              | _ -> failwith "Impossible : typechecker's work."
            in
            (* Get the variable *)
            let var = eval (Get(m)) in
            (* Evaluate before assigning *)
            let var_bop = eval (Binop(op, (value_to_expr var), e)) in
            (* Assign *)
            mem_acces m global_env local_env eval (assignment var_bop)
          in
          match s with
          | S_Set -> mem_acces m global_env local_env eval (assignment (eval e))
          | S_Add -> op_then_set Add
          | S_Sub -> op_then_set Sub
          | S_Mul -> op_then_set Mul
          | S_Div -> op_then_set Div
        end
      | While (e, s) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              begin
                exec_seq s local_env ;
                exec i
              end
            else
              ()
          | _ -> failwith "Impossible : typechecker's work"
        end
      | DoWhile (s, w) ->
        exec_seq s local_env ; (* do *)
        exec w (* while *)
      | Cond c -> exec_cond c
      | Return e -> raise (Return (eval e))
      | Expr e -> let _ = eval e in ()

    (* Execute a condition instruction [c] *)
    and exec_cond c =
      match c with
      | If (e, s) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              exec_seq s local_env
          | _ -> failwith "Impossible : typechecker's work"
        end
      | If_Else (e, s, c) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              exec_seq s local_env
            else
              exec_cond c
          | _ -> failwith "Impossible : typechecker's work"
        end
      | Else s -> exec_seq s local_env

    in
    (* Execute the sequence [s] *)
    List.iter exec s
  in
  exec_seq p.main (Hashtbl.create 1)