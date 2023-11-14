open Kawa

type value =
  | VInt  of int
  | VBool of bool
  | VObj  of obj
  | Null
and obj = {
  cls:    string;
  fields: (string, value) Hashtbl.t;
}

exception Error of string
exception Return of value

let exec_prog p =
  let global_env = Hashtbl.create 1 in
  List.iter (fun (x, _) -> Hashtbl.add global_env x Null) p.globals;
  
  let rec eval_call f this args =
    failwith "eval_call not implemented"

  and exec_seq s local_env =
    let rec eval_unop op e = 
      match op with
      | Opp ->
        begin
          match eval e with
          | VInt n -> VInt (-n)
          | _ -> failwith "type error: opposite operator can only be use on integers"
        end
      | Not ->
        begin
          match eval e with
          | VBool b -> VBool (not b)
          | _ -> failwith "type error: negative operator can only be use on booleans"
        end
      | _ -> assert false

    and eval_binop op e1 e2 =
      let num_to_num op =
         match eval e1, eval e2 with
          | VInt n1, VInt n2 -> VInt (op n1 n2)
          | _ -> failwith "type error: integer binary operator can only be use on integers"
      in let num_to_bool op =
        match eval e1, eval e2 with
          | VInt n1, VInt n2 -> VBool (op n1 n2)
          | _ -> failwith "type error: integer binary operator can only be use on integers"
      in let bool_to_bool op =
        match eval e1, eval e2 with
          | VBool b1, VBool b2 -> VBool (op b1 b2)
          | _ -> failwith "type error: boolean binary operator can only be use on booleans"
      in
      match op with
      | Add -> num_to_num ( + )
      | Sub -> num_to_num ( - )
      | Mul -> num_to_num ( * )
      | Div -> num_to_num ( / )
      | Mod -> num_to_num ( mod )
      | Le -> num_to_bool ( <= )
      | Lt -> num_to_bool ( < )
      | Ge -> num_to_bool ( >= )
      | Gt -> num_to_bool ( > )
      | Eq ->
        begin
          match eval e1, eval e2 with
          | VInt n1, VInt n2 -> VBool (n1 = n2)
          | VBool b1, VBool b2 -> VBool (b1 = b2)
          | _ -> failwith "type error: comparison can only be use on integers and booleans"
        end
      | Neq ->
        begin
          match eval e1, eval e2 with
          | VInt n1, VInt n2 -> VBool (n1 <> n2)
          | VBool b1, VBool b2 -> VBool (b1 <> b2)
          | _ -> failwith "type error: comparison can only be use on integers and booleans"
        end
      | And -> bool_to_bool ( && )
      | Or -> bool_to_bool ( || )
      | _ -> assert false

    and eval_new s el =
      let o = { cls = s ; fields = Hashtbl.create 1 } in
      let c =
        let rec find l =
          match l with
          | [] -> failwith ("unbound value error: '" ^ s ^ "' class is not declared in the scope.")
          | cl :: ll ->
            if cl.class_name = s then
              cl
            else
              find ll
        in
        find p.classes
      in
      let () = 
        begin
          match el with
          | None -> List.iter (fun (x, _) -> Hashtbl.add o.fields x Null ) c.attributes
          | Some el -> List.iter2 (fun (x, _) e -> Hashtbl.add o.fields x (eval e) ) c.attributes el
        end
      in 
      VObj o

    and eval e =
      match e with
      | Int n  -> VInt n
      | Bool b -> VBool b
      | Binop (op, e1, e2) -> eval_binop op e1 e2
      | Unop (op, e) -> eval_unop op e
      | TerCond(e1, e2, e3) ->
        begin
          match eval e1 with
          | VBool b ->
            if b then
              eval e2
            else
              eval e3 
          | _ -> failwith "type error: can't evaluate anything else than a boolean as a condition test" 
        end
      | Get m ->
        begin
          match m with
          | Var s ->
            begin 
              match Hashtbl.find_opt local_env s with
              | Some v -> v
              | None ->
                begin 
                  match Hashtbl.find_opt global_env s with
                  | Some v -> v
                  | None -> failwith ("unbound value error: '" ^ s ^ "' is not declared in the scope.")
                end
            end
          | _ -> failwith "case not implemented in eval::get"
        end
      | This -> Null (* TODO *)
      | New s -> eval_new s None
      | NewCstr (s, el) -> eval_new s (Some el)
      | _ -> assert false
    in
    let rec exec i = 
      match i with
      | Print e -> 
        begin
          match eval e with
          | VInt n -> Printf.printf "%d\n" n
          | VBool b -> Printf.printf "%s\n" (if b then "true" else "false")
          | _ -> failwith "type error: can't print other type than int or bool." 
        end
      | Set (m, e) ->
        begin
          match m with
          | Var s -> 
            begin 
              match Hashtbl.find_opt local_env s with
              | Some _ -> Hashtbl.add local_env s (eval e)
              | None ->
                begin 
                  match Hashtbl.find_opt global_env s with
                  | Some _ -> Hashtbl.add global_env s (eval e)
                  | None -> failwith ("unbound value error: '" ^ s ^ "' is not declared in the scope.")
                end
            end
          | _ -> failwith "case not implemented in exec::set"
        end
      | While (e, s) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              begin
                exec_seq s local_env ;
                exec_seq [ While(e, s) ] local_env
              end
            else
              ()
          | _ -> failwith "type error: can't evaluate anything else than a boolean as a condition test"
        end
      | DoWhile (s, w) ->
        exec_seq s local_env ;
        exec_seq [ w ] local_env
      | Cond c -> exec_cond c
      | _ -> failwith "case not implemented in exec"

    and exec_cond c =
      match c with
      | If (e, s) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              exec_seq s local_env
          | _ -> failwith "type error: can't evaluate anything else than a boolean as a condition test"
        end
      | If_Else (e, s, c) ->
        begin
          match eval e with
          | VBool b ->
            if b then
              exec_seq s local_env
            else
              exec_cond c
          | _ -> failwith "type error: can't evaluate anything else than a boolean as a condition test"
        end
      | Else s ->
        exec_seq s local_env
      | _ -> assert false

    in
    List.iter exec s
  in
  exec_seq p.main (Hashtbl.create 1)