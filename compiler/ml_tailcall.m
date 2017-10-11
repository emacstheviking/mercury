%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1999-2009 The University of Melbourne.
% Copyright (C) 2017 The Mercury Team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: ml_tailcall.m
% Authors: fjh, pbone
%
% This module is an MLDS-to-MLDS transformation that marks function calls
% as tail calls whenever it is safe to do so, based on the assumptions
% described below.
%
% A function call can safely be marked as a tail call if all three of the
% following conditions are satisfied:
%
% 1 it occurs in a position which would fall through into the end of the
%   function body or to a `return' statement,
%
% 2 the lvalues in which the return value(s) from the `call' will be placed
%   are the same as the value(s) returned by the `return', and these lvalues
%   are all local variables,
%
% 3 the function's local variables do not need to be live for that call.
%
% For (2), we just assume (rather than checking) that any variables returned
% by the `return' statement are local variables. This assumption is true
% for the MLDS code generated by ml_code_gen.m.
%
% For (3), we assume that the addresses of local variables and nested functions
% are only ever passed down to other functions (and used to assign to the local
% variable or to call the nested function), so that here we only need to check
% if the potential tail call uses such addresses, not whether such addresses
% were taken in earlier calls. That is, if the addresses of locals were taken
% in earlier calls from the same function, we assume that these addresses
% will not be saved (on the heap, or in global variables, etc.) and used after
% those earlier calls have returned. This assumption is true for the MLDS code
% generated by ml_code_gen.m.
%
% We just mark tailcalls in this module here. The actual tailcall optimization
% (turn self-tailcalls into loops) is done in ml_optimize. Individual backends
% may wish to treat tailcalls separately if there is any backend support
% for them.
%
% Note that ml_call_gen.m will also mark calls to procedures with determinism
% `erroneous' as `no_return_call's (a special case of tail calls)
% when it generates them.
%
% Note also that the job that this module does on the MLDS is very similar
% to the job done by mark_tail_calls.m on the HLDS. The two are separate
% because with the MLDS backend, figuring out which recursive calls will end up
% as tail calls cannot be done without doing a large part of the job of the
% HLDS-to-MLDS code generator. Nevertheless, what parts *can* be kept in common
% between this module and mark_tail_calls.m *should* be kept in common.
% This is why this module calls predicates in mark_tail_calls.m to construct
% the warning messages it generates.
%
%---------------------------------------------------------------------------%

:- module ml_backend.ml_tailcall.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module libs.
:- import_module libs.globals.
:- import_module ml_backend.mlds.
:- import_module parse_tree.
:- import_module parse_tree.error_util.

:- import_module list.

%---------------------------------------------------------------------------%

    % Traverse the MLDS, marking all optimizable tail calls as tail calls.
    %
    % If enabled, warn for calls that "look like" tail calls, but aren't.
    %
:- pred ml_mark_tailcalls(globals::in, module_info::in, list(error_spec)::out,
    mlds::in, mlds::out) is det.

:- type may_yield_dangling_stack_ref
    --->    may_yield_dangling_stack_ref
    ;       will_not_yield_dangling_stack_ref.

:- func may_rvals_yield_dangling_stack_ref(list(mlds_rval)) =
    may_yield_dangling_stack_ref.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module hlds.hlds_pred.
:- import_module hlds.mark_tail_calls.
:- import_module libs.compiler_util.
:- import_module libs.options.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module ml_backend.ml_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_pragma.

:- import_module bool.
:- import_module maybe.
:- import_module set.

%---------------------------------------------------------------------------%

ml_mark_tailcalls(Globals, ModuleInfo, Specs, !MLDS) :-
    ModuleName = mercury_module_name_to_mlds(!.MLDS ^ mlds_name),
    globals.lookup_bool_option(Globals, warn_non_tail_recursion_self,
        WarnTailCallsBool),
    (
        WarnTailCallsBool = yes,
        WarnTailCalls = warn_tail_calls
    ;
        WarnTailCallsBool = no,
        WarnTailCalls = do_not_warn_tail_calls
    ),
    FuncDefns0 = !.MLDS ^ mlds_proc_defns,
    list.map_foldl(
        mark_tailcalls_in_function_defn(ModuleInfo, ModuleName, WarnTailCalls),
        FuncDefns0, FuncDefns, [], Specs),
    !MLDS ^ mlds_proc_defns := FuncDefns.

%---------------------------------------------------------------------------%

    % We identify tail calls in the body of a function by walking backwards
    % through that body in the MLDS, tracking (via at_tail) whether a given
    % position in the body (either just before or just after a statement)
    % is in a tail position or not. The distinction between at_tail and
    % not_at_tail* records this.
    %
    % The `at_tail' functor indicates that the current statement is at a tail
    % position, i.e. it is followed by a return statement or the end of the
    % function. Its argument specifies the (possibly empty) vector of values
    % being returned.
    %
    % The `not_at_tail_seen_reccall' and `not_at_tail_have_not_seen_reccall'
    % functors indicate that the current statement is not at a tail position.
    % Which one reflects the current position depends on whether we have
    % already seen a recursive call in our backwards traversal. We use
    % this distinction to avoid creating warnings for recursive calls that are
    % obviously followed by the other, later recursive calls (like the first
    % recursive call in the double-recursive clause of quicksort).
    %
    % The reason why we need this distinction, and cannot just stop walking
    % backward through the function body when we find a recursive call
    % is code like this:
    %
    %   if (...) {
    %     ...
    %     recursive call 1
    %     return
    %   }
    %   ...
    %   recursive call 2
    %   return
    %
    % For such code, we *want* to continue our backwards traversal past
    % recursive call 2, so we can find recursive call 1.
    %
:- type at_tail
    --->        at_tail(list(mlds_rval))
    ;           not_at_tail_seen_reccall
    ;           not_at_tail_have_not_seen_reccall.

:- pred not_at_tail(at_tail::in, at_tail::out) is det.

not_at_tail(at_tail(_), not_at_tail_have_not_seen_reccall).
not_at_tail(not_at_tail_seen_reccall, not_at_tail_seen_reccall).
not_at_tail(not_at_tail_have_not_seen_reccall,
    not_at_tail_have_not_seen_reccall).

:- type tc_in_body_info
    --->    tc_in_body_info(
                tibi_found                  :: found_any_rec_calls,
                tibi_specs                  :: list(error_spec)
            ).

%---------------------------------------------------------------------------%

:- type tailcall_info
    --->    tailcall_info(
                tci_module_info             :: module_info,
                tci_module_name             :: mlds_module_name,
                tci_function_name           :: mlds_function_name,
                tci_warn_tail_calls         :: warn_tail_calls,
                tci_maybe_require_tailrec   :: maybe(require_tail_recursion)
            ).

:- type warn_tail_calls
    --->    warn_tail_calls
    ;       do_not_warn_tail_calls.

%---------------------------------------------------------------------------%

% mark_tailcalls_in_maybe_statement:
% mark_tailcalls_in_stmts:
% mark_tailcalls_in_stmt:
% mark_tailcalls_in_case:
% mark_tailcalls_in_default:
%   Recursively process the statement(s) and their components,
%   marking each optimizable tail call in them as a tail call.
%   The `AtTail' argument indicates whether or not this construct
%   is in a tail call position, and if not, whether we *have* seen a tailcall
%   earlier in the backwards traversal (i.e. after the current position,
%   in terms of forward execution).
%   The `Locals' argument contains the local definitions which are in scope
%   at the current point.

:- pred mark_tailcalls_in_function_defn(module_info::in, mlds_module_name::in,
    warn_tail_calls::in, mlds_function_defn::in, mlds_function_defn::out,
    list(error_spec)::in, list(error_spec)::out) is det.

mark_tailcalls_in_function_defn(ModuleInfo, ModuleName, WarnTailCalls,
        FuncDefn0, FuncDefn, !Specs) :-
    FuncDefn0 = mlds_function_defn(Name, Context, Flags,
        MaybePredProcId, Params, FuncBody0, Attributes,
        EnvVarNames, MaybeRequireTailrecInfo),
    (
        FuncBody0 = body_external,
        FuncDefn = FuncDefn0
    ;
        FuncBody0 = body_defined_here(BodyStmt0),
        Params = mlds_func_params(_Args, RetTypes),
        (
            RetTypes = [],
            AtTailAfter = at_tail([])
        ;
            RetTypes = [_ | _],
            AtTailAfter = not_at_tail_have_not_seen_reccall
        ),
        TCallInfo = tailcall_info(ModuleInfo, ModuleName, Name,
            WarnTailCalls, MaybeRequireTailrecInfo),

        InBodyInfo0 = tc_in_body_info(not_found_any_rec_calls, !.Specs),
        mark_tailcalls_in_stmt(TCallInfo, AtTailAfter, _AtTailBefore,
            BodyStmt0, BodyStmt, InBodyInfo0, InBodyInfo),
        InBodyInfo = tc_in_body_info(FoundRecCall, !:Specs),

        FuncBody = body_defined_here(BodyStmt),
        FuncDefn = mlds_function_defn(Name, Context, Flags,
            MaybePredProcId, Params, FuncBody, Attributes,
            EnvVarNames, MaybeRequireTailrecInfo),

        (
            MaybePredProcId = no
            % If this function wasn't generated from a Mercury predicate,
            % then we can't create this warning. This cannot happen anyway
            % because the require tail recursion pragma cannot be attached
            % to predicates that don't exist.
        ;
            MaybePredProcId = yes(PredProcId),
            module_info_pred_proc_info(ModuleInfo, PredProcId,
                PredInfo, ProcInfo),
            maybe_report_no_tail_or_nontail_recursive_calls(PredInfo, ProcInfo,
                FoundRecCall, !Specs)
        )
    ).

:- pred mark_tailcalls_in_maybe_statement(tailcall_info::in,
    at_tail::in, at_tail::out, maybe(mlds_stmt)::in, maybe(mlds_stmt)::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_maybe_statement(TCallInfo, !AtTail,
        MaybeStatement0, MaybeStatement, !InBodyInfo) :-
    (
        MaybeStatement0 = no,
        MaybeStatement = no
    ;
        MaybeStatement0 = yes(Statement0),
        mark_tailcalls_in_stmt(TCallInfo, !AtTail, Statement0, Statement,
            !InBodyInfo),
        MaybeStatement = yes(Statement)
    ).

:- pred mark_tailcalls_in_stmts(tailcall_info::in,
    at_tail::in, at_tail::out, list(mlds_stmt)::in, list(mlds_stmt)::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_stmts(_, !AtTail, [], [], !InBodyInfo).
mark_tailcalls_in_stmts(TCallInfo, !AtTail,
        [Stmt0 | Stmts0], [Stmt | Stmts], !InBodyInfo) :-
    mark_tailcalls_in_stmts(TCallInfo, !AtTail, Stmts0, Stmts,
        !InBodyInfo),
    mark_tailcalls_in_stmt(TCallInfo, !AtTail, Stmt0, Stmt,
        !InBodyInfo).

:- pred mark_tailcalls_in_stmt(tailcall_info::in,
    at_tail::in, at_tail::out, mlds_stmt::in, mlds_stmt::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_stmt(TCallInfo, AtTailAfter0, AtTailBefore,
        Stmt0, Stmt, !InBodyInfo) :-
    (
        Stmt0 = ml_stmt_block(LocalVarDefns, FuncDefns0, Stmts0, Context),
        % Whenever we encounter a block statement, we recursively mark
        % tailcalls in any nested functions defined in that block.
        % We also need to add any local definitions in that block to the list
        % of currently visible local declarations before processing the
        % statements in that block. The statement list will be in a tail
        % position iff the block is in a tail position.
        ModuleInfo = TCallInfo ^ tci_module_info,
        ModuleName = TCallInfo ^ tci_module_name,
        WarnTailCalls = TCallInfo ^ tci_warn_tail_calls,
        Specs0 = !.InBodyInfo ^ tibi_specs,
        list.map_foldl(
            mark_tailcalls_in_function_defn(ModuleInfo, ModuleName,
                WarnTailCalls),
            FuncDefns0, FuncDefns, Specs0, Specs),
        !InBodyInfo ^ tibi_specs := Specs,
        mark_tailcalls_in_stmts(TCallInfo, AtTailAfter0, AtTailBefore,
            Stmts0, Stmts, !InBodyInfo),
        Stmt = ml_stmt_block(LocalVarDefns, FuncDefns, Stmts, Context)
    ;
        Stmt0 = ml_stmt_while(Kind, Rval, Statement0, Context),
        % The statement in the body of a while loop is never in a tail
        % position.
        not_at_tail(AtTailAfter0, AtTailAfter),
        mark_tailcalls_in_stmt(TCallInfo, AtTailAfter, AtTailBefore0,
            Statement0, Statement, !InBodyInfo),
        % Neither is any statement before the loop.
        not_at_tail(AtTailBefore0, AtTailBefore),
        Stmt = ml_stmt_while(Kind, Rval, Statement, Context)
    ;
        Stmt0 = ml_stmt_if_then_else(Cond, Then0, MaybeElse0, Context),
        % Both the `then' and the `else' parts of an if-then-else are in a
        % tail position iff the if-then-else is in a tail position.
        mark_tailcalls_in_stmt(TCallInfo,
            AtTailAfter0, AtTailBeforeThen, Then0, Then, !InBodyInfo),
        mark_tailcalls_in_maybe_statement(TCallInfo,
            AtTailAfter0, AtTailBeforeElse, MaybeElse0, MaybeElse,
            !InBodyInfo),
        ( if
            ( AtTailBeforeThen = not_at_tail_seen_reccall
            ; AtTailBeforeElse = not_at_tail_seen_reccall
            )
        then
            AtTailBefore = not_at_tail_seen_reccall
        else
            AtTailBefore = not_at_tail_have_not_seen_reccall
        ),
        Stmt = ml_stmt_if_then_else(Cond, Then, MaybeElse, Context)
    ;
        Stmt0 = ml_stmt_switch(Type, Val, Range, Cases0, Default0, Context),
        % All of the cases of a switch (including the default) are in a
        % tail position iff the switch is in a tail position.
        mark_tailcalls_in_cases(TCallInfo, AtTailAfter0, AtTailBeforeCases,
            Cases0, Cases, !InBodyInfo),
        mark_tailcalls_in_default(TCallInfo, AtTailAfter0, AtTailBeforeDefault,
            Default0, Default, !InBodyInfo),
        ( if
            % Have we seen a tailcall, in either a case or in the default?
            (
                find_first_match(unify(not_at_tail_seen_reccall),
                    AtTailBeforeCases, _)
            ;
                AtTailBeforeDefault = not_at_tail_seen_reccall
            )
        then
            AtTailBefore = not_at_tail_seen_reccall
        else
            AtTailBefore = not_at_tail_have_not_seen_reccall
        ),
        Stmt = ml_stmt_switch(Type, Val, Range, Cases, Default, Context)
    ;
        Stmt0 = ml_stmt_call(_, _, _, _, _, _, _),
        mark_tailcalls_in_stmt_call(TCallInfo,
            AtTailAfter0, AtTailBefore, Stmt0, Stmt, !InBodyInfo)
    ;
        Stmt0 = ml_stmt_try_commit(Ref, Statement0, Handler0, Context),
        % Both the statement inside a `try_commit' and the handler are in
        % tail call position iff the `try_commit' statement is in a tail call
        % position.
        mark_tailcalls_in_stmt(TCallInfo, AtTailAfter0, _,
            Statement0, Statement, !InBodyInfo),
        mark_tailcalls_in_stmt(TCallInfo, AtTailAfter0, _,
            Handler0, Handler, !InBodyInfo),
        AtTailBefore = not_at_tail_have_not_seen_reccall,
        Stmt = ml_stmt_try_commit(Ref, Statement, Handler, Context)
    ;
        ( Stmt0 = ml_stmt_goto(_, _)
        ; Stmt0 = ml_stmt_computed_goto(_, _, _)
        ; Stmt0 = ml_stmt_do_commit(_, _)
        ; Stmt0 = ml_stmt_atomic(_, _)
        ),
        not_at_tail(AtTailAfter0, AtTailBefore),
        Stmt = Stmt0
    ;
        Stmt0 = ml_stmt_label(_, _),
        AtTailBefore = AtTailAfter0,
        Stmt = Stmt0
    ;
        Stmt0 = ml_stmt_return(ReturnVals, _Context),
        % The statement before a return statement is in a tail position.
        AtTailBefore = at_tail(ReturnVals),
        Stmt = Stmt0
    ).

:- pred mark_tailcalls_in_stmt_call(tailcall_info::in,
    at_tail::in, at_tail::out, mlds_stmt::in(ml_stmt_is_call), mlds_stmt::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_stmt_call(TCallInfo, AtTailAfter, AtTailBefore,
        Stmt0, Stmt, !InBodyInfo) :-
    Stmt0 = ml_stmt_call(Sig, CalleeRval, Args,
        CallReturnLvals, CallKind0, Markers, Context),
    ModuleName = TCallInfo ^ tci_module_name,
    FuncName = TCallInfo ^ tci_function_name,

    % Check if we can mark this call as a tail call.
    ( if
        CallKind0 = ordinary_call,
        CalleeRval = ml_const(mlconst_code_addr(CalleeCodeAddr)),
        % Currently, we can turn self-recursive calls into tail calls,
        % but we cannot do the same with mutually-recursive calls.
        % We therefore require the callee to be the same function
        % as the caller.
        code_address_is_for_this_function(CalleeCodeAddr, ModuleName, FuncName)
    then
        !InBodyInfo ^ tibi_found := found_any_rec_calls,
        ( if
            % We must be in a tail position.
            AtTailAfter = at_tail(ReturnStmtRvals),

            % The values returned in this call must match those returned
            % by the `return' statement that follows.
            call_returns_same_local_lvals_as_return_stmt(ReturnStmtRvals,
                CallReturnLvals),

            % The call must not take the address of any local variables
            % or nested functions.
            may_rvals_yield_dangling_stack_ref(Args) =
                will_not_yield_dangling_stack_ref

            % The call must not be to a function nested within this function,
            % but a recursive call can *never* be so nested.
        then
            % Mark this call as a tail call.
            Stmt = ml_stmt_call(Sig, CalleeRval, Args,
                CallReturnLvals, tail_call, Markers, Context),
            AtTailBefore = not_at_tail_seen_reccall
        else
            (
                AtTailAfter = not_at_tail_seen_reccall
            ;
                (
                    AtTailAfter = not_at_tail_have_not_seen_reccall
                ;
                    % This might happen if one of the other tests above fails.
                    % If so, a warning may be useful.
                    AtTailAfter = at_tail(_)
                ),
                maybe_warn_tailcalls(TCallInfo, CalleeCodeAddr, Markers,
                    Context, !InBodyInfo)
            ),
            Stmt = Stmt0,
            AtTailBefore = not_at_tail_seen_reccall
        )
    else
        % Leave this call unchanged.
        Stmt = Stmt0,
        not_at_tail(AtTailAfter, AtTailBefore)
    ).

:- pred mark_tailcalls_in_cases(tailcall_info::in,
    at_tail::in, list(at_tail)::out,
    list(mlds_switch_case)::in, list(mlds_switch_case)::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_cases(_, _, [], [], [], !InBodyInfo).
mark_tailcalls_in_cases(TCallInfo, AtTailAfter, [AtTailBefore | AtTailBefores],
        [Case0 | Cases0], [Case | Cases], !InBodyInfo) :-
    mark_tailcalls_in_case(TCallInfo, AtTailAfter, AtTailBefore,
        Case0, Case, !InBodyInfo),
    mark_tailcalls_in_cases(TCallInfo, AtTailAfter, AtTailBefores,
        Cases0, Cases, !InBodyInfo).

:- pred mark_tailcalls_in_case(tailcall_info::in, at_tail::in, at_tail::out,
    mlds_switch_case::in, mlds_switch_case::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_case(TCallInfo, AtTailAfter, AtTailBefore,
        Case0, Case, !InBodyInfo) :-
    Case0 = mlds_switch_case(FirstCond, LaterConds, Statement0),
    mark_tailcalls_in_stmt(TCallInfo, AtTailAfter, AtTailBefore,
        Statement0, Statement, !InBodyInfo),
    Case = mlds_switch_case(FirstCond, LaterConds, Statement).

:- pred mark_tailcalls_in_default(tailcall_info::in, at_tail::in, at_tail::out,
    mlds_switch_default::in, mlds_switch_default::out,
    tc_in_body_info::in, tc_in_body_info::out) is det.

mark_tailcalls_in_default(TCallInfo, AtTailAfter, AtTailBefore,
        Default0, Default, !InBodyInfo) :-
    (
        ( Default0 = default_is_unreachable
        ; Default0 = default_do_nothing
        ),
        AtTailBefore = AtTailAfter,
        Default = Default0
    ;
        Default0 = default_case(Statement0),
        mark_tailcalls_in_stmt(TCallInfo, AtTailAfter, AtTailBefore,
            Statement0, Statement, !InBodyInfo),
        Default = default_case(Statement)
    ).

%---------------------------------------------------------------------------%

:- pred maybe_warn_tailcalls(tailcall_info::in, mlds_code_addr::in,
    set(ml_call_marker)::in, prog_context::in,
    tc_in_body_info::in, tc_in_body_info::out) is det.

maybe_warn_tailcalls(TCallInfo, CodeAddr, Markers, Context, !InBodyInfo) :-
    WarnTailCalls = TCallInfo ^ tci_warn_tail_calls,
    MaybeRequireTailrecInfo = TCallInfo ^ tci_maybe_require_tailrec,
    ( if
        % Trivially reject the common case.
        WarnTailCalls = do_not_warn_tail_calls,
        MaybeRequireTailrecInfo = no
    then
        true
    else if
        require_complete_switch [WarnTailCalls]
        (
            WarnTailCalls = do_not_warn_tail_calls,

            % We always warn/error if the pragma says so.
            MaybeRequireTailrecInfo = yes(RequireTailrecInfo),
            RequireTailrecInfo = enable_tailrec_warnings(WarnOrError,
                TailrecType, _)
        ;
            WarnTailCalls = warn_tail_calls,

            % if warnings are enabled then we check the pragma. We check
            % that it doesn't disable warnings and also determine whether
            % this should be a warning or error.
            require_complete_switch [MaybeRequireTailrecInfo]
            (
                MaybeRequireTailrecInfo = no,
                % Choose some defaults.
                WarnOrError = we_warning,
                TailrecType = both_self_and_mutual_recursion_must_be_tail
            ;
                MaybeRequireTailrecInfo = yes(RequireTailrecInfo),
                require_complete_switch [RequireTailrecInfo]
                (
                    RequireTailrecInfo =
                        enable_tailrec_warnings(WarnOrError, TailrecType, _)
                ;
                    RequireTailrecInfo = suppress_tailrec_warnings(_),
                    false
                )
            )
        ),
        require_complete_switch [TailrecType]
        (
            TailrecType = both_self_and_mutual_recursion_must_be_tail
        ;
            TailrecType = only_self_recursion_must_be_tail
            % XXX: Currently this has no effect since all tailcalls on MLDS
            % are direct tail calls.
        )
    then
        CodeAddr = mlds_code_addr(QualFuncLabel, _Sig),
        QualFuncLabel = qual_func_label(_ModuleName, FuncLabel),
        FuncLabel = mlds_func_label(ProcLabel, _MaybeSeqNum),
        ProcLabel = mlds_proc_label(PredLabel, ProcId),
        (
            PredLabel = mlds_special_pred_label(_, _, _, _)
            % Don't warn about special preds.
        ;
            PredLabel = mlds_user_pred_label(PredOrFunc, _MaybeModule,
                Name, Arity, _CodeModel, _NonOutputFunc),
            ( if set.contains(Markers, mcm_disable_non_tail_rec_warning) then
                true
            else
                SymName = unqualified(Name),
                SimpleCallId = simple_call_id(PredOrFunc, SymName, Arity),
                Specs0 = !.InBodyInfo ^ tibi_specs,
                add_message_for_nontail_self_recursive_call(SimpleCallId,
                    ProcId, Context, ntrcr_program, WarnOrError,
                    Specs0, Specs),
                !InBodyInfo ^ tibi_specs := Specs
            )
        )
    else
        true
    ).

%---------------------------------------------------------------------------%

% call_returns_same_local_lvals_as_return_stmt(ReturnStmtRvals,
%   CallReturnLvals):
% call_returns_same_local_lval_as_return_stmt(ReturnStmtRval,
%   CallReturnLval):
%
%   Check that the lval(s) returned by a call match the rval(s) in the
%   `return' statement that follows, and those lvals are local variables
%   (so that assignments to them won't have any side effects),
%   so that we can optimize the call into a tailcall.

:- pred call_returns_same_local_lvals_as_return_stmt(list(mlds_rval)::in,
    list(mlds_lval)::in) is semidet.

call_returns_same_local_lvals_as_return_stmt([], []).
call_returns_same_local_lvals_as_return_stmt(
        [ReturnStmtRval | ReturnStmtRvals],
        [CallReturnLval | CallReturnLvals]) :-
    call_returns_same_local_lval_as_return_stmt(ReturnStmtRval,
        CallReturnLval),
    call_returns_same_local_lvals_as_return_stmt(ReturnStmtRvals,
        CallReturnLvals).

:- pred call_returns_same_local_lval_as_return_stmt(mlds_rval::in,
    mlds_lval::in) is semidet.

call_returns_same_local_lval_as_return_stmt(ReturnStmtRval, CallReturnLval) :-
    ReturnStmtRval = ml_lval(CallReturnLval),
    lval_is_local(CallReturnLval) = is_local.

:- type is_local
    --->    is_local
    ;       is_not_local.

:- func lval_is_local(mlds_lval) = is_local.

lval_is_local(Lval) = IsLocal :-
    (
        Lval = ml_local_var(_, _),
        IsLocal = is_local
    ;
        Lval = ml_field(_Tag, Rval, _Field, _, _),
        % A field of a local variable is local.
        ( if Rval = ml_mem_addr(BaseLval) then
            IsLocal = lval_is_local(BaseLval)
        else
            IsLocal = is_not_local
        )
    ;
        ( Lval = ml_mem_ref(_Rval, _Type)
        ; Lval = ml_global_var(_, _)
        ; Lval = ml_target_global_var_ref(_)
        ),
        IsLocal = is_not_local
    ).

%---------------------------------------------------------------------------%

% may_rvals_yield_dangling_stack_ref:
% may_maybe_rval_yield_dangling_stack_ref:
% may_rval_yield_dangling_stack_ref:
%   Find out if the specified rval(s) might evaluate to the addresses of
%   local variables (or fields of local variables) or nested functions.

may_rvals_yield_dangling_stack_ref([]) = will_not_yield_dangling_stack_ref.
may_rvals_yield_dangling_stack_ref([Rval | Rvals])
        = MayYieldDanglingStackRef :-
    MayYieldDanglingStackRef0 =
        may_rval_yield_dangling_stack_ref(Rval),
    (
        MayYieldDanglingStackRef0 = may_yield_dangling_stack_ref,
        MayYieldDanglingStackRef = may_yield_dangling_stack_ref
    ;
        MayYieldDanglingStackRef0 = will_not_yield_dangling_stack_ref,
        MayYieldDanglingStackRef =
            may_rvals_yield_dangling_stack_ref(Rvals)
    ).

:- func may_rval_yield_dangling_stack_ref(mlds_rval)
    = may_yield_dangling_stack_ref.

may_rval_yield_dangling_stack_ref(Rval) = MayYieldDanglingStackRef :-
    (
        Rval = ml_lval(_Lval),
        % Passing the _value_ of an lval is fine.
        MayYieldDanglingStackRef = will_not_yield_dangling_stack_ref
    ;
        Rval = ml_mkword(_Tag, SubRval),
        MayYieldDanglingStackRef =
            may_rval_yield_dangling_stack_ref(SubRval)
    ;
        Rval = ml_const(Const),
        MayYieldDanglingStackRef = check_const(Const)
    ;
        Rval = ml_unop(_Op, SubRval),
        MayYieldDanglingStackRef =
            may_rval_yield_dangling_stack_ref(SubRval)
    ;
        Rval = ml_binop(_Op, SubRvalA, SubRvalB),
        MayYieldDanglingStackRefA =
            may_rval_yield_dangling_stack_ref(SubRvalA),
        (
            MayYieldDanglingStackRefA = may_yield_dangling_stack_ref,
            MayYieldDanglingStackRef = may_yield_dangling_stack_ref
        ;
            MayYieldDanglingStackRefA = will_not_yield_dangling_stack_ref,
            MayYieldDanglingStackRef =
                may_rval_yield_dangling_stack_ref(SubRvalB)
        )
    ;
        Rval = ml_mem_addr(Lval),
        % Passing the address of an lval is a problem,
        % if that lval names a local variable.
        MayYieldDanglingStackRef =
            may_lval_yield_dangling_stack_ref(Lval)
    ;
        Rval = ml_vector_common_row_addr(_VectorCommon, RowRval),
        MayYieldDanglingStackRef =
            may_rval_yield_dangling_stack_ref(RowRval)
    ;
        ( Rval = ml_scalar_common(_)
        ; Rval = ml_scalar_common_addr(_)
        ; Rval = ml_self(_)
        ),
        MayYieldDanglingStackRef = may_yield_dangling_stack_ref
    ).

    % Find out if the specified lval might be a local variable
    % (or a field of a local variable).
    %
:- func may_lval_yield_dangling_stack_ref(mlds_lval)
    = may_yield_dangling_stack_ref.

may_lval_yield_dangling_stack_ref(Lval) = MayYieldDanglingStackRef :-
    (
        Lval = ml_local_var(_Var0, _),
        MayYieldDanglingStackRef = may_yield_dangling_stack_ref
    ;
        Lval = ml_field(_MaybeTag, Rval, _FieldId, _, _),
        MayYieldDanglingStackRef = may_rval_yield_dangling_stack_ref(Rval)
    ;
        ( Lval = ml_mem_ref(_, _)
        ; Lval = ml_global_var(_, _)
        ; Lval = ml_target_global_var_ref(_)
        ),
        % We assume that the addresses of local variables are only ever
        % passed down to other functions, or assigned to, so a mem_ref lval
        % can never refer to a local variable.
        MayYieldDanglingStackRef = will_not_yield_dangling_stack_ref
    ).

    % Find out if the specified const might be the address of a local variable
    % or nested function.
    %
    % The addresses of local variables are probably not consts, at least
    % not unless those variables are declared as static (i.e. `one_copy'),
    % so it might be safe to allow all data_addr_consts here, but currently
    % we just take a conservative approach.
    %
:- func check_const(mlds_rval_const) = may_yield_dangling_stack_ref.

check_const(Const) = MayYieldDanglingStackRef :-
    (
        Const = mlconst_code_addr(CodeAddr),
        ( if function_is_local(CodeAddr) then
            MayYieldDanglingStackRef = may_yield_dangling_stack_ref
        else
            MayYieldDanglingStackRef = will_not_yield_dangling_stack_ref
        )
    ;
        Const = mlconst_data_addr_local_var(_VarName),
        MayYieldDanglingStackRef = may_yield_dangling_stack_ref
    ;
        ( Const = mlconst_true
        ; Const = mlconst_false
        ; Const = mlconst_int(_)
        ; Const = mlconst_uint(_)
        ; Const = mlconst_int8(_)
        ; Const = mlconst_uint8(_)
        ; Const = mlconst_int16(_)
        ; Const = mlconst_uint16(_)
        ; Const = mlconst_int32(_)
        ; Const = mlconst_uint32(_)
        ; Const = mlconst_enum(_, _)
        ; Const = mlconst_char(_)
        ; Const = mlconst_foreign(_, _, _)
        ; Const = mlconst_float(_)
        ; Const = mlconst_string(_)
        ; Const = mlconst_multi_string(_)
        ; Const = mlconst_named_const(_, _)
        ; Const = mlconst_data_addr_rtti(_, _)
        ; Const = mlconst_data_addr_tabling(_, _)
        ; Const = mlconst_data_addr_global_var(_, _)
        ; Const = mlconst_null(_)
        ),
        MayYieldDanglingStackRef = will_not_yield_dangling_stack_ref
    ).

    % Check whether the specified function is defined locally (i.e. as a
    % nested function).
    %
:- pred function_is_local(mlds_code_addr::in) is semidet.

function_is_local(CodeAddr) :-
    CodeAddr = mlds_code_addr(QualFuncLabel, _Signature),
    QualFuncLabel = qual_func_label(_ModuleName, FuncLabel),
    FuncLabel = mlds_func_label(_ProcLabel, MaybeAux),
    require_complete_switch [MaybeAux]
    (
        MaybeAux = proc_func,
        fail
    ;
        ( MaybeAux = proc_aux_func(_)
        ; MaybeAux = gc_trace_for_proc_func
        ; MaybeAux = gc_trace_for_proc_aux_func(_)
        )
    ).

%---------------------------------------------------------------------------%
:- end_module ml_backend.ml_tailcall.
%---------------------------------------------------------------------------%
