%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% 
% file: trailing_analysis.m
% author: juliensf
%
% This module implements trail usage analysis.  It annotates the HLDS with
% information about which procedures may modify the trail.
%
% It intended to be used in helping the compiler decide when it is safe to
% omit trailing operations in trailing grades.  After running the analysis
% the trailing status of each procedure is one of:
%
%   (1) will_not_modify_trail
%   (2) may_modify_trail
%   (3) conditional
% 
% These have the following meaning:
%
%   (1) for all inputs the procedure will not modify the trail.
%   (2) for some inputs the procedure may modify the trail.
%   (3) the procedure is polymorphic and whether it may modify the trail
%       depends upon the instantiation of the type variables.  We need
%       this because we can define types with user-defined equality or
%       comparison that modify the trail.
%
% NOTE: to be `conditional' a procedure cannot modify the trail itself,
% any trail modifications that occur through the conditional procedure
% must result from a higher-order call or a call to a user-defined equality
% or comparison predicate.
%
% For procedures defined using the foreign language interface we rely upon
% the user annotations, `will_not_modify_trail' and `may_not_modify_trail'.
%
% The predicates for determining if individual goals modify the trail
% are in goal_form.m.
% 
% TODO:
%   - Rather than using the predicates in goal_form.m., annotate each
%     goal with trail usage information.  These would prevent multiple
%     traversals of the goal structure.  It would also make it easier
%     to do "clever" things during the trailing transformation.
%
%   - Use the results of closure analysis to determine the trailing
%     status of higher-order calls.
%
%----------------------------------------------------------------------------%

:- module transform_hlds.trailing_analysis.

:- interface.

:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.

:- import_module io.

    % Perform trailing analysis on a module.
    %
:- pred analyse_trail_usage(module_info::in, module_info::out,
    io::di, io::uo) is det.

    % Write out the trailing_info pragma for this module.
    %
:- pred write_pragma_trailing_info(module_info::in, trailing_info::in,
    pred_id::in, io::di, io::uo) is det.

%----------------------------------------------------------------------------%
%----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.mode_util.
:- import_module check_hlds.type_util.
:- import_module hlds.code_model.
:- import_module hlds.hlds_error_util.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_pred.
:- import_module hlds.make_hlds.
:- import_module hlds.passes_aux.
:- import_module hlds.special_pred.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.error_util.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.modules.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_util.
:- import_module parse_tree.prog_type.
:- import_module transform_hlds.dependency_graph.

:- import_module bool.
:- import_module list.
:- import_module map.
:- import_module set.
:- import_module std_util.
:- import_module string.
:- import_module term.

%----------------------------------------------------------------------------%
%
% Perform trail usage analysis on a module
%

analyse_trail_usage(!ModuleInfo, !IO) :-
    globals.io_lookup_bool_option(use_trail, UseTrail, !IO),
    (
        % Only run the analysis in trailing grades.
        UseTrail = yes,
        module_info_ensure_dependency_info(!ModuleInfo),
        module_info_dependency_info(!.ModuleInfo, DepInfo),
        hlds_dependency_info_get_dependency_ordering(DepInfo, SCCs),
        globals.io_lookup_bool_option(debug_trail_usage, Debug, !IO),
        list.foldl2(process_scc(Debug), SCCs, !ModuleInfo, !IO),
        globals.io_lookup_bool_option(make_optimization_interface,
            MakeOptInt, !IO),
        (
            MakeOptInt = yes,
            make_opt_int(!.ModuleInfo, !IO)
        ;
            MakeOptInt = no
        )  
    ;
        UseTrail = no
    ).
%----------------------------------------------------------------------------%
% 
% Perform trail usage analysis on a SCC 
%

:- type scc == list(pred_proc_id).

:- type proc_results == list(proc_result).

:- type proc_result
    ---> proc_result(
            ppid :: pred_proc_id,
            status :: trailing_status
    ).

:- pred process_scc(bool::in, scc::in,
    module_info::in, module_info::out, io::di, io::uo) is det.

process_scc(Debug, SCC, !ModuleInfo, !IO) :-
    ProcResults = check_procs_for_trail_mods(SCC, !.ModuleInfo),
    % 
    % The `Results' above are the results of analysing each individual
    % procedure in the SCC - we now have to combine them in a meaningful way.   
    %
    Status = combine_individual_proc_results(ProcResults),
    %
    % Print out debugging information.
    %
    (
        Debug = yes,
        dump_trail_usage_debug_info(!.ModuleInfo, SCC, Status, !IO)
    ;
        Debug = no
    ),
    %
    % Update the trailing_info with information about this SCC.
    %
    module_info_get_trailing_info(!.ModuleInfo, TrailingInfo0),
    Update = (pred(PPId::in, Info0::in, Info::out) is det :-
        Info = Info0 ^ elem(PPId) := Status
    ),
    list.foldl(Update, SCC, TrailingInfo0, TrailingInfo),
    module_info_set_trailing_info(TrailingInfo, !ModuleInfo). 

    % Check each procedure in the SCC individually.
    %
:- func check_procs_for_trail_mods(scc, module_info) = proc_results.

check_procs_for_trail_mods(SCC, ModuleInfo) = Result :-
    list.foldl(check_proc_for_trail_mods(SCC, ModuleInfo), SCC, [], Result).

    % Examine how the procedures interact with other procedures that
    % are mutually-recursive to them.
    %
:- func combine_individual_proc_results(proc_results) = trailing_status.

combine_individual_proc_results([]) = _ :-
    unexpected(this_file, "Empty SCC during trailing analysis.").
combine_individual_proc_results(ProcResults @ [_|_]) = SCC_Result :- 
    (
        % If none of the procedures modifies the trail or is conditional then
        % the SCC cannot modify the trail.
        all [ProcResult] list.member(ProcResult, ProcResults) =>
            ProcResult ^ status = will_not_modify_trail
    ->
        SCC_Result = will_not_modify_trail
    ;
        all [EResult] list.member(EResult, ProcResults) =>
                EResult ^ status \= may_modify_trail,
        some [CResult] (
            list.member(CResult, ProcResults),
            CResult ^ status = conditional
        )
    ->
        SCC_Result = conditional
    ;
        % Otherwise the SCC may modify the trail.
        SCC_Result = may_modify_trail
    ).

%----------------------------------------------------------------------------%
%
% Perform trail usage analysis on a procedure
% 

:- pred check_proc_for_trail_mods(scc::in, module_info::in,
    pred_proc_id::in, proc_results::in, proc_results::out) is det.

check_proc_for_trail_mods(SCC, ModuleInfo, PPId, !Results) :-
    module_info_pred_proc_info(ModuleInfo, PPId, _, ProcInfo),
    proc_info_goal(ProcInfo, Body),
    proc_info_vartypes(ProcInfo, VarTypes),
    check_goal_for_trail_mods(SCC, ModuleInfo, VarTypes, Body, Result),
    list.cons(proc_result(PPId, Result), !Results).

%----------------------------------------------------------------------------%
%
% Perform trail usage analysis of a goal
%

:- pred check_goal_for_trail_mods(scc::in, module_info::in, vartypes::in,
    hlds_goal::in, trailing_status::out) is det.  

check_goal_for_trail_mods(SCC, ModuleInfo, VarTypes, Goal - GoalInfo,
        Result) :-
    check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, Goal, GoalInfo,
        Result).

:- pred check_goal_for_trail_mods_2(scc::in, module_info::in, vartypes::in,
    hlds_goal_expr::in, hlds_goal_info::in, trailing_status::out) is det.

check_goal_for_trail_mods_2(_, _, _, Goal, _, will_not_modify_trail) :-
    Goal = unify(_, _, _, Kind, _),
    ( Kind = complicated_unify(_, _, _) ->
        unexpected(this_file, "complicated unify during trail usage analysis.")
    ;
        true
    ).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, Goal, _, Result) :-
    Goal = call(CallPredId, CallProcId, CallArgs, _, _, _),
    CallPPId = proc(CallPredId, CallProcId),    
    module_info_pred_info(ModuleInfo, CallPredId, CallPredInfo),
    (
        % Handle (mutually-)recursive calls.
        list.member(CallPPId, SCC) 
    ->
        Types = list.map((func(Var) = VarTypes ^ det_elem(Var)), CallArgs),
        TrailingStatus = check_types(ModuleInfo, Types),
        Result = TrailingStatus
    ; 
        pred_info_is_builtin(CallPredInfo) 
    ->
        % There are no builtins that will modify the trail.
        Result = will_not_modify_trail
    ;
        % Handle unify and compare.
        (
            ModuleName = pred_info_module(CallPredInfo),
            any_mercury_builtin_module(ModuleName),
            Name = pred_info_name(CallPredInfo),
            Arity = pred_info_orig_arity(CallPredInfo),
            ( SpecialPredId = spec_pred_compare
            ; SpecialPredId = spec_pred_unify
            ),
            special_pred_name_arity(SpecialPredId, Name, _, Arity)
        ;
            pred_info_get_origin(CallPredInfo, Origin),
            Origin = special_pred(SpecialPredId - _),
            ( SpecialPredId = spec_pred_compare
            ; SpecialPredId = spec_pred_unify
            )
        )   
    ->
        % At the moment we assume that calls to out-of-line
        % unification/comparisons are going to modify the trail.
        % XXX This is far too conservative.
        Result = may_modify_trail
    ;
        % Handle library predicates whose trailing status
        % can be looked up in the known procedures table.
        Name = pred_info_name(CallPredInfo),
        PredOrFunc = pred_info_is_pred_or_func(CallPredInfo),
        ModuleName = pred_info_module(CallPredInfo),
        ModuleName = unqualified(ModuleNameStr),
        Arity = pred_info_orig_arity(CallPredInfo),
        known_procedure(PredOrFunc, ModuleNameStr, Name, Arity, Result0)
    ->
        Result = Result0
    ;
        check_nonrecursive_call(ModuleInfo, VarTypes, CallPPId, CallArgs,
            Result)
    ).
check_goal_for_trail_mods_2(_, _ModuleInfo, _VarTypes, Goal, _GoalInfo,
        Result) :-
    Goal = generic_call(Details, _Args, _ArgModes, _),
    (
        % XXX Use results of closure analysis to handle this.
        Details = higher_order(_Var, _, _,  _),
        Result = may_modify_trail
    ;
        % XXX We could do better with class methods.
        Details = class_method(_, _, _, _),
        Result = may_modify_trail
    ;
        Details = cast(_),
        Result  = will_not_modify_trail
    ;
        % XXX I'm not sure what the correct thing to do for 
        % aditi builtins is.
        Details = aditi_builtin(_, _),
        Result = may_modify_trail
    ).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, not(Goal), _,
        Result) :-
    check_goal_for_trail_mods(SCC, ModuleInfo, VarTypes, Goal, Result).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, Goal, OuterGoalInfo,
        Result) :-
    Goal = scope(_, InnerGoal),
    check_goal_for_trail_mods(SCC, ModuleInfo, VarTypes, InnerGoal, Result0),
    InnerGoal = _ - InnerGoalInfo,
    goal_info_get_code_model(InnerGoalInfo, InnerCodeModel),
    goal_info_get_code_model(OuterGoalInfo, OuterCodeModel),
    (
        % If we're at a commit for Goal that might modify the trail then we
        % will need to emit some trailing code around the scope goal.
        InnerCodeModel = model_non,
        OuterCodeModel \= model_non,
        Result0 \= will_not_modify_trail
    ->
        Result = may_modify_trail 
    ;   
        Result = Result0 
    ).
check_goal_for_trail_mods_2(_, _, _, Goal, _, Result) :-
    Goal = foreign_proc(Attributes, _, _, _, _, _),
    %
    % XXX polymorphic foreign calls.
    ( may_modify_trail(Attributes) = may_modify_trail ->
        Result = may_modify_trail
    ;
        Result = will_not_modify_trail
    ).
check_goal_for_trail_mods_2(_, _, _, shorthand(_), _, _) :-
    unexpected(this_file,
        "shorthand goal encountered during trailing analysis.").
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, Goal, _, Result) :-
    Goal = switch(_, _, Cases),
    CaseGoals = list.map((func(case(_, CaseGoal)) = CaseGoal), Cases),
    check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, CaseGoals, Result).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, Goal, _, Result) :-
    Goal = if_then_else(_, If, Then, Else),
    check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, [If, Then, Else],
        Result0),
    (
        % If none of the disjuncts can modify the trail then we don't need
        % to emit trailing code around this disjunction.
        Result0 = will_not_modify_trail,
        Result  = will_not_modify_trail
    ;
        % XXX In the case where this is conditional we could do better
        % by creating specialised versions of the procedure.
        ( Result0 = conditional ; Result0 = may_modify_trail),
        Result = may_modify_trail
    ).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, conj(Goals), _,
        Result) :-
    check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, Goals, Result).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, par_conj(Goals), _,
        Result) :-
    check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, Goals, Result).
check_goal_for_trail_mods_2(SCC, ModuleInfo, VarTypes, disj(Goals), _,
        Result) :-
    check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, Goals, Result0),
    (
        % If none of the disjuncts can modify the trail then we don't need
        % to emit trailing code around this disjunction.
        Result0 = will_not_modify_trail,
        Result  = will_not_modify_trail
    ;
        % One or or more of the disjuncts may modify the trail, so
        % we need to emit the trailing code - XXX could do better by
        % specialising conditional code.
        ( Result0 = conditional ; Result0 = may_modify_trail),
        Result = may_modify_trail
    ).

:- pred check_goals_for_trail_mods(scc::in, module_info::in, vartypes::in,
    hlds_goals::in, trailing_status::out) is det.

check_goals_for_trail_mods(SCC, ModuleInfo, VarTypes, Goals, Result) :-
    list.map(check_goal_for_trail_mods(SCC, ModuleInfo, VarTypes), Goals,
        Results),
    list.foldl(combine_trailing_status, Results, will_not_modify_trail,
        Result).

%----------------------------------------------------------------------------%
%
% "Known" library procedures
%

% known_procedure/4 is a table of library predicates whose trailing
% status is hardcoded into the analyser.  For a few predicates this
% information can make a big difference (particularly in the absence
% of any form of intermodule analysis).

:- pred known_procedure(pred_or_func::in, string::in, string::in, int::in,
    trailing_status::out) is semidet.

known_procedure(predicate, "require", "error", 1, will_not_modify_trail).
known_procedure(function,  "require", "func_error", 1, will_not_modify_trail).
known_procedure(_, "exception", "throw", 1, will_not_modify_trail).

%----------------------------------------------------------------------------%
%
% Further code to handle higher-order variables
% 
    % Extract those procedures whose trailing_status has been set to
    % `conditional'.  Fails if one of the procedures in the set 
    % is known to modify the trail or if the trailing status is not
    % yet been set for one or more of the procedures.
    %
    % XXX The latter case probably shouldn't happen but may at the
    % moment because the construction of the dependency graph doesn't
    % take higher-order calls into account.
    % 
:- pred get_conditional_closures(module_info::in, set(pred_proc_id)::in,
    list(pred_proc_id)::out) is semidet.

get_conditional_closures(ModuleInfo, Closures, Conditionals) :-
    module_info_get_trailing_info(ModuleInfo, TrailingInfo),
    set.fold(get_conditional_closure(TrailingInfo), Closures,
        [], Conditionals).

:- pred get_conditional_closure(trailing_info::in, pred_proc_id::in,
    list(pred_proc_id)::in, list(pred_proc_id)::out) is semidet.

get_conditional_closure(TrailingInfo, PPId, !Conditionals) :-
    TrailingInfo ^ elem(PPId) = Status,
    (
        Status = conditional,
        list.cons(PPId, !Conditionals)
    ;
        Status = will_not_modify_trail
    ).

%----------------------------------------------------------------------------%

:- pred combine_trailing_status(trailing_status::in, trailing_status::in,
    trailing_status::out) is det.

combine_trailing_status(will_not_modify_trail, Y, Y).
combine_trailing_status(may_modify_trail, _, may_modify_trail).
combine_trailing_status(conditional, will_not_modify_trail, conditional).
combine_trailing_status(conditional, conditional, conditional).
combine_trailing_status(conditional, may_modify_trail, may_modify_trail).

%----------------------------------------------------------------------------%
% 
% Extra procedures for handling calls
%

:- pred check_nonrecursive_call(module_info::in, vartypes::in,
    pred_proc_id::in, prog_vars::in, trailing_status::out) is det.

check_nonrecursive_call(ModuleInfo, VarTypes, PPId, Args, Result) :-
    module_info_get_trailing_info(ModuleInfo, TrailingInfo),
    ( map.search(TrailingInfo, PPId, CalleeTrailingStatus) ->
        (
            CalleeTrailingStatus = will_not_modify_trail,
            Result = will_not_modify_trail
        ;
            CalleeTrailingStatus = may_modify_trail,
            Result = may_modify_trail
        ;
            CalleeTrailingStatus = conditional,
            %
            % This is a call to a polymorphic procedure.  We need to make
            % sure that none of the types involved has a user-defined
            % equality or comparison predicate that modifies the trail.
            % XXX Need to handle higher-order args here as well.
            Result = check_vars(ModuleInfo, VarTypes, Args) 
        )
    ;
        % If we do not have any information about the callee procedure then
        % assume that it modifies the trail.
        Result = may_modify_trail
    ).

:- func check_vars(module_info, vartypes, prog_vars) = trailing_status.

check_vars(ModuleInfo, VarTypes, Vars) = Result :- 
    Types = list.map((func(Var) = VarTypes ^ det_elem(Var)), Vars),
    Result = check_types(ModuleInfo, Types).

%----------------------------------------------------------------------------%
% 
% Stuff for processing types
%

% This is used in the analysis of calls to polymorphic procedures.
%
% By saying a `type may modify the trail' we mean that tail modification
% may occur as a result of a unification or comparison involving the type
% because it has a user-defined equality/comparison predicate that modifies
% the trail.
%
% XXX We don't actually need to examine all the types, just those
% that are potentially going to be involved in unification/comparisons.
% (The exception and termination analyses have the same problem.)
%
% At the moment we don't keep track of that information so the current
% procedure is as follows:
%
% Examine the functor and then recursively examine the arguments.
% * If everything will not will_not_modify_trail then the type will not
%   modify the trail.
%
% * If at least one of the types may modify the trail then the type will
%   will modify the trail.
%
% * If at least one of the types is conditional and none of them throw then
%   the type is conditional.

    % Return the collective trailing status of a list of types.
    %
:- func check_types(module_info, list(mer_type)) = trailing_status.

check_types(ModuleInfo, Types) = Status :-
    list.foldl(check_type(ModuleInfo), Types, will_not_modify_trail, Status).

:- pred check_type(module_info::in, mer_type::in, trailing_status::in,
    trailing_status::out) is det.

check_type(ModuleInfo, Type, !Status) :-
    combine_trailing_status(check_type(ModuleInfo, Type), !Status). 

    % Return the trailing status of an individual type.
    %
:- func check_type(module_info, mer_type) = trailing_status.

check_type(ModuleInfo, Type) = Status :-
    ( 
        ( is_solver_type(ModuleInfo, Type)
        ; is_existq_type(ModuleInfo, Type))
     ->
        % XXX At the moment we just assume that existential
        % types and solver types may modify the trail.
        Status = may_modify_trail
    ;   
        TypeCategory = classify_type(ModuleInfo, Type),
        Status = check_type_2(ModuleInfo, Type, TypeCategory)
    ).

:- func check_type_2(module_info, mer_type, type_category) = trailing_status.

check_type_2(_, _, type_cat_int) = will_not_modify_trail.
check_type_2(_, _, type_cat_char) = will_not_modify_trail.
check_type_2(_, _, type_cat_string) = will_not_modify_trail.
check_type_2(_, _, type_cat_float) = will_not_modify_trail.
check_type_2(_, _, type_cat_higher_order) = will_not_modify_trail.
check_type_2(_, _, type_cat_type_info) = will_not_modify_trail. 
check_type_2(_, _, type_cat_type_ctor_info) = will_not_modify_trail.
check_type_2(_, _, type_cat_typeclass_info) = will_not_modify_trail.
check_type_2(_, _, type_cat_base_typeclass_info) = will_not_modify_trail.
check_type_2(_, _, type_cat_void) = will_not_modify_trail.
check_type_2(_, _, type_cat_dummy) = will_not_modify_trail.

check_type_2(_, _, type_cat_variable) = conditional.

check_type_2(ModuleInfo, Type, type_cat_tuple) =
    check_user_type(ModuleInfo, Type).
check_type_2(ModuleInfo, Type, type_cat_enum) =
    check_user_type(ModuleInfo, Type). 
check_type_2(ModuleInfo, Type, type_cat_user_ctor) =
    check_user_type(ModuleInfo, Type). 

:- func check_user_type(module_info, mer_type) = trailing_status.

check_user_type(ModuleInfo, Type) = Status :-
    ( type_to_ctor_and_args(Type, _TypeCtor, Args) ->
        ( 
            type_has_user_defined_equality_pred(ModuleInfo, Type,
                _UnifyCompare)
        ->
            % XXX We can do better than this by examining
            % what these preds actually do.  Something
            % similar needs to be sorted out for termination
            % analysis as well, so we'll wait until that is
            % done.
            Status = may_modify_trail
        ;
            Status = check_types(ModuleInfo, Args)
        )
    ;
        unexpected(this_file, "Unable to get ctor and args.")
    ). 

%----------------------------------------------------------------------------%
%
% Stuff for intermodule optimization
% 

:- pred trailing_analysis.make_opt_int(module_info::in, io::di, io::uo)
    is det.

trailing_analysis.make_opt_int(ModuleInfo, !IO) :-
    module_info_get_name(ModuleInfo, ModuleName),
    module_name_to_file_name(ModuleName, ".opt.tmp", no, OptFileName, !IO),
    globals.io_lookup_bool_option(verbose, Verbose, !IO),
    maybe_write_string(Verbose, "% Appending trailing_info pragmas to `", !IO),
    maybe_write_string(Verbose, OptFileName, !IO),
    maybe_write_string(Verbose, "'...", !IO),
    maybe_flush_output(Verbose, !IO),
    io.open_append(OptFileName, OptFileRes, !IO),
    (
        OptFileRes = ok(OptFile),
        io.set_output_stream(OptFile, OldStream, !IO),
        module_info_get_trailing_info(ModuleInfo, TrailingInfo), 
        module_info_predids(ModuleInfo, PredIds),   
        list.foldl(write_pragma_trailing_info(ModuleInfo, TrailingInfo),
            PredIds, !IO),
        io.set_output_stream(OldStream, _, !IO),
        io.close_output(OptFile, !IO),
        maybe_write_string(Verbose, " done.\n", !IO)
    ;
        OptFileRes = error(IOError),
        maybe_write_string(Verbose, " failed!\n", !IO),
        io.error_message(IOError, IOErrorMessage),
        io.write_strings(["Error opening file `",
            OptFileName, "' for output: ", IOErrorMessage], !IO),
        io.set_exit_status(1, !IO)
    ).  

write_pragma_trailing_info(ModuleInfo, TrailingInfo, PredId, !IO) :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_import_status(PredInfo, ImportStatus),
    (   
        ( ImportStatus = exported 
        ; ImportStatus = opt_exported 
        ),
        not is_unify_or_compare_pred(PredInfo),
        module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
        TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
        not set.member(PredId, TypeSpecForcePreds),
        %
        % XXX Writing out pragmas for the automatically generated class
        % instance methods causes the compiler to abort when it reads them
        % back in.
        %
        pred_info_get_markers(PredInfo, Markers),
        not check_marker(Markers, class_instance_method),
        not check_marker(Markers, named_class_instance_method)
    ->
        ModuleName = pred_info_module(PredInfo),
        Name       = pred_info_name(PredInfo),
        Arity      = pred_info_orig_arity(PredInfo),
        PredOrFunc = pred_info_is_pred_or_func(PredInfo),
        ProcIds    = pred_info_procids(PredInfo),
        list.foldl((pred(ProcId::in, !.IO::di, !:IO::uo) is det :-
            proc_id_to_int(ProcId, ModeNum),
            ( 
                map.search(TrailingInfo, proc(PredId, ProcId), Status)
            ->
                mercury_output_pragma_trailing_info(PredOrFunc, 
                    qualified(ModuleName, Name), Arity,
                    ModeNum, Status, !IO)
            ;
                true
            )), ProcIds, !IO)
    ;
        true
    ).          

%----------------------------------------------------------------------------%
%
% Code for printing out debugging traces
%
 
:- pred dump_trail_usage_debug_info(module_info::in, scc::in,
    trailing_status::in, io::di, io::uo) is det.

dump_trail_usage_debug_info(ModuleInfo, SCC, Status, !IO) :-
    io.write_string("SCC: ", !IO),
    io.write(Status, !IO),
    io.nl(!IO),
    output_proc_names(ModuleInfo, SCC, !IO),
    io.nl(!IO).

:- pred output_proc_names(module_info::in, scc::in, io::di, io::uo) is det.

output_proc_names(ModuleInfo, SCC, !IO) :-
    list.foldl(output_proc_name(ModuleInfo), SCC, !IO).

:- pred output_proc_name(module_info::in, pred_proc_id::in,
    io::di, io::uo) is det.
output_proc_name(Moduleinfo, PPId, !IO) :-
   Pieces = describe_one_proc_name(Moduleinfo, should_module_qualify, PPId), 
   Str = error_pieces_to_string(Pieces),
   io.format("\t%s\n", [s(Str)], !IO).

%----------------------------------------------------------------------------%

:- func this_file = string.

this_file = "trailing_analysis.m".

%----------------------------------------------------------------------------%
:- end_module trailing_analysis.
%----------------------------------------------------------------------------%
