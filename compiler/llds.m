%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% LLDS - The Low-Level Data Structure.

% This module defines both the LLDS data structure itself, and also
% the routines for printing it out.

% Main authors: conway, fjh.

%-----------------------------------------------------------------------------%

:- module llds.		
:- interface.
:- import_module io, std_util, list, set, term, string, int, float.
:- import_module tree, shapes.

%-----------------------------------------------------------------------------%

:- type code_model	--->	model_det		% functional & total
			;	model_semi		% just functional
			;	model_non.		% not functional

:- type c_file		--->	c_file(string, list(c_module)).
			%	filename, modules

:- type c_module	--->	c_module(string, list(c_procedure)).
			%	module name, code

:- type c_procedure	--->	c_procedure(string, int, llds__proc_id,
						list(instruction)).
			%	predicate name, arity, mode, code
:- type llds__proc_id == int.

:- type code_tree	==	tree(list(instruction)).

:- type instruction	==	pair(instr, string).
			%	 instruction, comment

:- type instr	
	--->	comment(string)
			% Insert a comment into the output code.

	;	livevals(set(lval))
			% A list of which registers and stack locations
			% are currently live.

	;	block(int, list(instruction))
			% A list of instructions that make use of
			% some local temporary variables.

	;	assign(lval, rval)
			% Assign the value specified by rval to the location
			% specified by lval.

	;	call(code_addr, code_addr, code_addr, list(liveinfo)) 
			% call(Target, Continuation) is the same as
			% succip = Continuation; goto(Target).
			% The third code_addr is the entry address for
			% the caller predicate and is used for profiling.

	;	call_closure(code_model, code_addr, list(liveinfo))
			% Setup the arguments and branch to a higher
			% order call. The closure is in r1 and the
			% input arguments are in r2, r3, ...
			% The output arguments are in r1, r2, ...
			% except for semidet calls, where they are in r2, ...

	;	mkframe(string, int, code_addr)
			% mkframe(Comment, SlotCount, FailureContinuation)
			% creates a nondet stack frame.

	;	modframe(code_addr)
			% modframe(FailureContinuation) is the same as
			% current_redoip = FailureContinuation.

	;	label(label)

	;	goto(code_addr, code_addr)
			% goto(Target, CallerAddress)
			% Branch to the specified address.
			% Note that jumps to do_fail, etc., can get
			% optimized into the invocations of macros fail(), etc..
			% CallerAddress is needed for profiling,
			% when tailcall optimization is turned on.

	;	computed_goto(rval, list(label))
			% Evaluate rval, which should be an integer,
			% and jump to the (rval+1)th label in the list.
			% e.g. computed_goto(2, [A, B, C, D])
			% will branch to label C.

	;	c_code(string)
			% Do whatever is specified by the string,
			% which can be any piece of C code that
			% does not have any non-local flow of control.

	;	if_val(rval, code_addr)
			% If rval is true, then goto code_addr.

	;	incr_hp(lval, maybe(tag), rval)
			% Get a memory block of a given size
			% and put its address in the given lval,
			% possibly after tagging it with an rval.

	;	mark_hp(lval)
			% Tell the heap sub-system to store a marker
			% (for later use in restore_hp/1 instructions)
			% in the specified lval

	;	restore_hp(rval)
			% The rval must be a marker as returned by mark_hp/1.
			% The effect is to deallocate all the memory which
			% was allocated since that call to mark_hp.

	;	incr_sp(int)
			% Increment the det stack pointer.

	;	decr_sp(int).
			% Decrement the det stack pointer.

:- type liveinfo	--->	live_lvalue(lval, shape_num).

:- type lval		--->	reg(reg)	% either an int or float reg
			;	stackvar(int)	% det stack slots
			;	framevar(int)	% nondet stack slots
			;	succip		% det return address
			;	maxfr		% top of nondet stack
			;	curfr		% nondet stack frame pointer
			;	redoip(rval)	% the redoip of the named
						% nondet stack frame
			;	succfr(rval)	
			;	prevfr(rval)	
			;	hp		% heap pointer
			;	sp		% top of det stack
			;	field(tag, rval, rval)
			;	lvar(var)
			;	temp(int).	% only inside blocks

:- type rval		--->	lval(lval)
			;	var(var)
			;	create(tag, list(maybe(rval)), int)
				% tag, arguments, label number
				% The label number is needed for the case when
				% we can construct the term at compile-time
				% and just reference the label.
				% Only constant term create() rvals should
				% get output, others will get transformed
				% to incr_hp(..., Tag, Size) plus
				% assignments to the fields
			;	mkword(tag, rval)
			;	const(rval_const)
			;	unop(unary_op, rval)
			;	binop(binary_op, rval, rval).

			/* any additions to `rval' also require additions in
			   code_info__generate_expression
			   code_info__generate_expression_vars
			   code_info__expression_dependencies
			   value_number__make_live
			*/

:- type rval_const	--->	true
			;	false
			;	int_const(int)
			;	float_const(float)
			;	string_const(string)
			;	address_const(code_addr).

:- type unary_op	--->	mktag
			;	tag
			;	unmktag
			;	mkbody
			;	body
			;	unmkbody
			;	cast_to_unsigned
			;	hash_string
			;	bitwise_complement
			;	(not).

:- type binary_op	--->	(+)	% integer arithmetic
			;	(-)
			;	(*)
			;	(/)
			;	(mod)
			;	(<<)	% left shift
			;	(>>)	% right shift
			;	(&)	% bitwise and
			;	('|')	% bitwise or
			;	(^)	% bitwise xor
			;	(and)	% logical and
			;	(or)	% logical or
			;	eq	% ==
			;	ne	% !=
			;	array_index
			;	str_eq	% string comparisons
			;	str_ne	
			;	str_lt
			;	str_gt
			;	str_le
			;	str_ge
			;	(<)	% integer comparions
			;	(>)
			;	(<=)
			;	(>=)
			;	float_plus
			;	float_minus
			;	float_times
			;	float_divide
			;	float_eq
			;	float_ne
			;	float_lt
			;	float_gt
			;	float_le
			;	float_ge.

:- type reg		--->	r(int)		% integer regs
			;	f(int).		% floating point regs

	% local(proc_label)
	%	local entry label
	% local(proc_label, int, cont_type)
	%	internal local label which can only be accessed externaly if
	%	it is a continuation label.  The cont_type is if it is a cont
	%	label, and whether the predicate is exported
	% exported(proc_label)
	%	entry label, which can be accessed from any where.

:- type label
	--->		local(proc_label)
	;		local(proc_label, int, cont_type)
	;		exported(proc_label).

:- type cont_type
	--->		unknown
	;		no
	;		local
	;		exported.

:- type code_addr
	--->		label(label)
	;		imported(proc_label)
	;		succip
	;		do_succeed(bool)
	;		do_redo
	;		do_fail.

:- type proc_label 	
	--->	proc(string, string, int, int)
		%	 module, predicate name, predicate arity, mode #
	;	special_proc(string, string, string, int, int).
		%	module, pred name, type name, type arity, mode #

:- type tag		==	int.

	% Given a 'c_file' structure, open the appropriate .mod file
	% and output the code into that file.

:- pred output_c_file(c_file, io__state, io__state).
:- mode output_c_file(in, di, uo) is det.

	% Convert an lval to a string description of that lval.

:- pred llds__lval_to_string(lval, string).
:- mode llds__lval_to_string(in, out) is semidet.

:- pred llds__binary_op_to_string(binary_op, string).
:- mode llds__binary_op_to_string(in, out) is det.

	% Output an instruction (used for debugging).

:- pred output_instruction(instr, io__state, io__state).
:- mode output_instruction(in, di, uo) is det.

	% Output a label (used by garbage collection).

:- pred output_label(label, io__state, io__state).
:- mode output_label(in, di, uo) is det.

%-----------------------------------------------------------------------------%

:- implementation.
:- import_module char, require, globals, options.
:- import_module exprn_aux.

%-----------------------------------------------------------------------------%

output_c_file(c_file(BaseName, Modules)) -->
	{ string__append(BaseName, ".c", FileName) },
	io__tell(FileName, Result),
	(
		{ Result = ok }
	->
		io__write_string("/* this code automatically generated - do not edit.*/\n\n"),
		io__write_string("/*\n"),
		io__write_string("INIT "),
		output_init_name(BaseName),
		io__write_string("\n"),
		io__write_string("ENDINIT\n"),
		io__write_string("*/\n\n"),
		io__write_string("#include ""imp.h""\n"),
		output_c_module_list(Modules),
		io__write_string("\n"),
		output_c_module_init_list(BaseName, Modules),
		io__told
	;
		io__progname_base("llds.m", ProgName),
		io__write_string("\n"),
		io__write_string(ProgName),
		io__write_string(": can't open `"),
		io__write_string(FileName),
		io__write_string("' for output\n"),
		io__set_exit_status(1)
	).

:- pred output_c_module_init_list(string, list(c_module), io__state, io__state).
:- mode output_c_module_init_list(in, in, di, uo) is det.

output_c_module_init_list(BaseName, Modules) -->
	io__write_string("static void "),
	output_bunch_name(BaseName, 0),
	io__write_string("(void)\n"),
	io__write_string("{\n"),
	output_c_module_init_list_2(Modules, BaseName, 0, 40, 0, InitFuncs),
	io__write_string("}\n\n"),
	io__write_string("void "),
	output_init_name(BaseName),
	io__write_string("(void); /* suppress gcc warning */\n"),
	io__write_string("void "),
	output_init_name(BaseName),
	io__write_string("(void)\n"),
	io__write_string("{\n"),
	output_c_module_init_list_3(0, BaseName, InitFuncs),
	io__write_string("}\n").

:- pred output_c_module_init_list_2(list(c_module), string, int, int, int, int,
	io__state, io__state).
:- mode output_c_module_init_list_2(in, in, in, in, in, out, di, uo) is det.

output_c_module_init_list_2([], _, _, _, InitFunc, InitFunc) --> [].
output_c_module_init_list_2([c_module(ModuleName, _) | Ms], BaseName,
		Calls0, MaxCalls, InitFunc0, InitFunc) -->
	( { Calls0 > MaxCalls } ->
		io__write_string("}\n\n"),
		{ InitFunc1 is InitFunc0 + 1 },
		io__write_string("static void "),
		output_bunch_name(BaseName, InitFunc1),
		io__write_string("(void)\n"),
		io__write_string("{\n"),
		{ Calls1 = 1 }
	;
		{ InitFunc1 = InitFunc0 },
		{ Calls1 is Calls0 + 1 }
	),
	io__write_string("\t"),
	output_module_name(ModuleName),
	io__write_string("();\n"),
	output_c_module_init_list_2(Ms, BaseName,
		Calls1, MaxCalls, InitFunc1, InitFunc).

:- pred output_c_module_init_list_3(int, string, int, io__state, io__state).
:- mode output_c_module_init_list_3(in, in, in, di, uo) is det.

output_c_module_init_list_3(InitFunc0, BaseName, MaxInitFunc) -->
	( { InitFunc0 > MaxInitFunc } ->
		[]
	;
		io__write_string("\t"),
		output_bunch_name(BaseName, InitFunc0),
		io__write_string("();\n"),
		{ InitFunc1 is InitFunc0 + 1},
		output_c_module_init_list_3(InitFunc1, BaseName, MaxInitFunc)
	).

:- pred output_init_name(string, io__state, io__state).
:- mode output_init_name(in, di, uo) is det.

output_init_name(BaseName) -->
	io__write_string("mercury__"),
	io__write_string(BaseName),
	io__write_string("__init").

:- pred output_bunch_name(string, int, io__state, io__state).
:- mode output_bunch_name(in, in, di, uo) is det.

output_bunch_name(BaseName, Number) -->
	io__write_string("mercury__"),
	io__write_string(BaseName),
	io__write_string("_bunch_"),
	io__write_int(Number).

:- pred output_module_name(string, io__state, io__state).
:- mode output_module_name(in, di, uo) is det.

output_module_name(ModuleName) -->
	io__write_string("mercury__"),
	io__write_string(ModuleName).

:- pred output_c_module_list(list(c_module), io__state, io__state).
:- mode output_c_module_list(in, di, uo) is det.

output_c_module_list([]) --> [].
output_c_module_list([M|Ms]) -->
	output_c_module(M),
	output_c_module_list(Ms).

:- pred output_c_module(c_module, io__state, io__state).
:- mode output_c_module(in, di, uo) is det.

output_c_module(c_module(ModuleName, Procedures)) -->
	{ gather_labels(Procedures, Labels) },
	io__write_string("\n"),
	output_c_label_decl_list(Labels),
	io__write_string("\n"),
	io__write_string("BEGIN_MODULE("),
	output_module_name(ModuleName),
	io__write_string(")\n"),
	output_c_label_init_list(Labels),
	io__write_string("BEGIN_CODE\n"),
	io__write_string("\n"),
	output_c_procedure_list(Procedures),
	io__write_string("END_MODULE\n").

:- pred output_c_label_decl_list(list(label), io__state, io__state).
:- mode output_c_label_decl_list(in, di, uo) is det.

output_c_label_decl_list(Labels) -->
	globals__io_lookup_int_option(procs_per_c_function, ProcsPerFunc),
	output_c_label_decl_list_2(Labels, ProcsPerFunc).

:- pred output_c_label_decl_list_2(list(label), int, io__state, io__state).
:- mode output_c_label_decl_list_2(in, in, di, uo) is det.

output_c_label_decl_list_2([], _) --> [].
output_c_label_decl_list_2([Label | Labels], ProcsPerFunc) -->
	output_c_label_decl(Label, ProcsPerFunc),
	output_c_label_decl_list_2(Labels, ProcsPerFunc).

:- pred output_c_label_decl(label, int, io__state, io__state).
:- mode output_c_label_decl(in, in, di, uo) is det.

output_c_label_decl(Label, ProcsPerFunc) -->
	(
		{ Label = exported(_) },
		io__write_string("Define_extern_entry("),
		output_label(Label),
		io__write_string(");\n")
	;
		{ Label = local(_) },
		( { ProcsPerFunc = 0 } ->
			io__write_string("Declare_local("),
			output_label(Label),
			io__write_string(");\n")
		;
			io__write_string("Define_extern_entry("),
			output_label(Label),
			io__write_string(");\n")
		)
	;
		{ Label = local(_, _, _) },
		io__write_string("Declare_label("),
		output_label(Label),
		io__write_string(");\n")
	).

:- pred output_c_label_init_list(list(label), io__state, io__state).
:- mode output_c_label_init_list(in, di, uo) is det.

output_c_label_init_list(Labels) -->
	globals__io_lookup_int_option(procs_per_c_function, ProcsPerFunc),
	output_c_label_init_list_2(Labels, ProcsPerFunc).

:- pred output_c_label_init_list_2(list(label), int, io__state, io__state).
:- mode output_c_label_init_list_2(in, in, di, uo) is det.

output_c_label_init_list_2([], _) --> [].
output_c_label_init_list_2([Label | Labels], ProcsPerFunc) -->
	output_c_label_init(Label, ProcsPerFunc),
	output_c_label_init_list_2(Labels, ProcsPerFunc).

:- pred output_c_label_init(label, int, io__state, io__state).
:- mode output_c_label_init(in, in, di, uo) is det.

output_c_label_init(Label, ProcPerFunc) -->
	(
		{ Label = exported(_) },
		io__write_string("\tinit_entry("),
		output_label(Label),
		io__write_string(");\n")
	;
		{ Label = local(_) },
		( { ProcPerFunc = 0 } ->
			io__write_string("\tinit_local("),
			output_label(Label),
			io__write_string(");\n")
		;
			io__write_string("\tinit_entry("),
			output_label(Label),
			io__write_string(");\n")
		)
	;
		{ Label = local(_, _, _) },
		io__write_string("\tinit_label("),
		output_label(Label),
		io__write_string(");\n")
	).

	% The following code is very straightforward and
	% unremarkable.  The only thing of note is that is
	% uses the logical io library, and that it uses DCGs
	% to avoid having to explicitly shuffle the state-of-the-world
	% arguments around all the time, as discussed in my hons thesis. -fjh.

:- pred output_c_procedure_list(list(c_procedure), io__state, io__state).
:- mode output_c_procedure_list(in, di, uo) is det.

output_c_procedure_list([]) --> [].
output_c_procedure_list([P|Ps]) -->
	output_c_procedure(P),
	output_c_procedure_list(Ps).

:- pred output_c_procedure(c_procedure, io__state, io__state).
:- mode output_c_procedure(in, di, uo) is det.

output_c_procedure(c_procedure(Name,Arity,ModeNum0,Instructions)) -->
	globals__io_lookup_bool_option(mod_comments, PrintModComments),
	( { PrintModComments = yes } ->
		io__write_string("\n/*-------------------------------------"),
		io__write_string("------------------------------------*/\n")
	;
		[]
	),
	io__write_string("/* code for predicate "),
	io__write_string(Name),
	io__write_string("/"),
	io__write_int(Arity),
	io__write_string(" in mode "),
	{ ModeNum is ModeNum0 mod 10000 },	% strip off the priority
	io__write_int(ModeNum),
	io__write_string(" */\n"),
	output_instruction_list(Instructions).

:- pred output_instruction_list(list(instruction), io__state, io__state).
:- mode output_instruction_list(in, di, uo) is det.

output_instruction_list([]) --> [].
output_instruction_list([Inst - Comment|Instructions]) -->
	globals__io_lookup_bool_option(mod_comments, PrintModComments),
	( { PrintModComments = no, Inst = comment(_) } ->
		[]
	;
		output_instruction(Inst),
		io__write_string("\n")
	),
	(
		{ Comment \= "" },
		{ PrintModComments = yes }
	->
		io__write_string("\t\t/* "),
		io__write_string(Comment),
		io__write_string(" */\n")
	;
		[]
	),
	output_instruction_list(Instructions).

output_instruction(comment(Comment)) -->
	globals__io_lookup_bool_option(mod_comments, PrintModComments),
	(
		{ Comment \= "" },
		{ PrintModComments = yes }
	->
		io__write_strings(["/* ", Comment, " */"])
	;
		[]
	).

output_instruction(livevals(LiveVals)) -->
	globals__io_lookup_bool_option(mod_comments, PrintModComments),
	(
		{ PrintModComments = yes }
	->
		io__write_string("/*\n * Live lvalues:\n"),
		{ set__to_sorted_list(LiveVals, LiveValsList) },
		output_livevals(LiveValsList),
		io__write_string(" */")
	;
		[]
	).

output_instruction(block(N, Instrs)) -->
	io__write_string("\t{ Word "),
	output_temp_decls(N),
	io__write_string(";\n"),
	output_instruction_list(Instrs),
	io__write_string("\t}\n").

output_instruction(assign(Lval, Rval)) -->
	io__write_string("\t{ "),
	output_lval_decls(Lval),
	output_rval_decls(Rval),
	output_lval(Lval),
	io__write_string(" = "),
	output_rval(Rval),
	io__write_string("; }").

output_instruction(call(Target, Continuation, CallerAddress, LiveVals)) -->
	io__write_string("\t{ "),
	output_code_addr_decls(Target),
	output_code_addr_decls(Continuation),
	output_code_addr_decls(CallerAddress),
	output_call(Target, Continuation, CallerAddress),
	io__write_string(" }\n"),
	output_gc_livevals(LiveVals).

output_instruction(call_closure(IsSemidet, Continuation, LiveVals)) -->
	io__write_string("\t{ "),
	output_code_addr_decls(Continuation),
	output_call_closure(IsSemidet, Continuation),
	io__write_string(" }\n"),
	output_gc_livevals(LiveVals).

output_instruction(c_code(C_Code_String)) -->
	io__write_string("\t"),
	io__write_string(C_Code_String).

output_instruction(mkframe(Str, Num, FailureContinuation)) -->
	io__write_string("\t{ "),
	output_code_addr_decls(FailureContinuation),
	io__write_string("mkframe("""),
	io__write_string(Str),
	io__write_string(""", "),
	io__write_int(Num),
	io__write_string(", "),
	output_code_addr(FailureContinuation),
	io__write_string("); }").

output_instruction(modframe(FailureContinuation)) -->
	io__write_string("\t{ "),
	output_code_addr_decls(FailureContinuation),
	io__write_string("modframe("),
	output_code_addr(FailureContinuation),
	io__write_string("); }").

output_instruction(label(Label)) -->
	output_label_defn(Label),
	maybe_output_update_prof_counter(Label).
	
output_instruction(goto(CodeAddr, CallerAddr)) -->
	io__write_string("\t{ "),
	output_code_addr_decls(CodeAddr),
	output_code_addr_decls(CallerAddr),
	output_goto(CodeAddr, CallerAddr),
	io__write_string(" }").

output_instruction(computed_goto(Rval, Labels)) -->
	io__write_string("\t{ "),
	output_rval_decls(Rval),
	io__write_string("COMPUTED_GOTO("),
	output_rval(Rval),
	io__write_string(",\n\t\t"),
	output_label_list(Labels),
	io__write_string("); }").

output_instruction(if_val(Rval, Target)) -->
	io__write_string("\t{ "),
	output_rval_decls(Rval),
	output_code_addr_decls(Target),
	io__write_string("if ("),
	output_rval(Rval),
	io__write_string(")\n\t\t"),
	output_goto(Target, Target),
	io__write_string(" }").

output_instruction(incr_hp(Lval, MaybeTag, Rval)) -->
	(
		{ MaybeTag = no },
		io__write_string("\t{ "),
		output_lval_decls(Lval),
		output_rval_decls(Rval),
		io__write_string("incr_hp("),
		output_lval(Lval),
		io__write_string(", "),
		output_rval(Rval),
		io__write_string("); }")
	;
		{ MaybeTag = yes(Tag) },
		io__write_string("\t{ "),
		output_lval_decls(Lval),
		output_rval_decls(Rval),
		io__write_string("tag_incr_hp("),
		output_lval(Lval),
		io__write_string(", "),
		output_tag(Tag),
		io__write_string(", "),
		output_rval(Rval),
		io__write_string("); }")
	).

output_instruction(mark_hp(Lval)) -->
	io__write_string("\t{ "),
	output_lval_decls(Lval),
	io__write_string("mark_hp("),
	output_lval(Lval),
	io__write_string("); }").

output_instruction(restore_hp(Rval)) -->
	io__write_string("\t{ "),
	output_rval_decls(Rval),
	io__write_string("restore_hp("),
	output_rval(Rval),
	io__write_string("); }").

output_instruction(incr_sp(N)) -->
	io__write_string("\t"),
	io__write_string("incr_sp("),
	io__write_int(N),
	io__write_string(");").

output_instruction(decr_sp(N)) -->
	io__write_string("\t"),
	io__write_string("decr_sp("),
	io__write_int(N),
	io__write_string(");").

:- pred output_livevals(list(lval), io__state, io__state).
:- mode output_livevals(in, di, uo) is det.

output_livevals([]) --> [].
output_livevals([Lval|Lvals]) -->
	io__write_string(" *\t"),
	output_lval(Lval),
	io__write_string("\n"),
	output_livevals(Lvals).

:- pred output_gc_livevals(list(liveinfo), io__state, io__state).
:- mode output_gc_livevals(in, di, uo) is det.

output_gc_livevals(LiveVals) -->
	globals__io_lookup_bool_option(mod_comments, PrintModComments),
	( { PrintModComments = yes } ->
		io__write_string("/*\n"),
		io__write_string(" * Garbage collection livevals info\n"),
		output_gc_livevals_2(LiveVals),
		io__write_string(" */")
	;
		[]
	).

:- pred output_gc_livevals_2(list(liveinfo), io__state, io__state).
:- mode output_gc_livevals_2(in, di, uo) is det.

output_gc_livevals_2([]) --> [].
output_gc_livevals_2([live_lvalue(Lval, Shape)|Lvals]) -->
	io__write_string(" *\t"),
	output_lval(Lval),
	io__write_string("\t"),
	shapes__write_shape_num(Shape),
	io__write_string("\n"),
	output_gc_livevals_2(Lvals).

:- pred output_temp_decls(int, io__state, io__state).
:- mode output_temp_decls(in, di, uo) is det.

output_temp_decls(N) --> 
	output_temp_decls_2(1, N).

:- pred output_temp_decls_2(int, int, io__state, io__state).
:- mode output_temp_decls_2(in, in, di, uo) is det.

output_temp_decls_2(Next, Max) --> 
	( { Next =< Max } ->
		( { Next > 1 } ->
			io__write_string(", ")
		;
			[]
		),
		io__write_string("temp"),
		io__write_int(Next),
		{ Next1 is Next + 1 },
		output_temp_decls_2(Next1, Max)
	;
		[]
	).

:- pred output_rval_decls(rval, io__state, io__state).
:- mode output_rval_decls(in, di, uo) is det.

output_rval_decls(lval(Lval)) --> 
	output_lval_decls(Lval).
output_rval_decls(var(_)) --> 
	{ error("output_rval_decls: unexpected var") }.
output_rval_decls(mkword(_, Rval)) --> 
	output_rval_decls(Rval).
output_rval_decls(const(Const)) -->
	( { Const = address_const(CodeAddress) } ->
		output_code_addr_decls(CodeAddress)
	;
		[]
	).
output_rval_decls(unop(_, Rval)) -->
	output_rval_decls(Rval).
output_rval_decls(binop(_, Rval1, Rval2)) -->
	output_rval_decls(Rval1),
	output_rval_decls(Rval2).

	%
	% Originally we used to output static constants as
	%
	%	static const Word mercury_const_...[] = { ... };
	%
	% However, if the initializer contains any code addresses,
	% this causes problems with gcc when using shared libraries,
	% because the constant will need to be dynamically linked,
	% but gcc notices that it is of type `Word' which is not a pointer
	% type and hence assumes that it will not need relocation,
	% and places it in the `rdata' section.  This causes minor
	% problems with Solaris: if you use gcc 2.7 and link with `gcc -shared',
	% you get a link error; the work-around is to link with `gcc -G'.
	% It also causes major problems with Irix 5: the relocation is not
	% done, resulting in a core dump at runtime.
	%
	% The gcc maintainers said that this was a bug in our code, since it
	% converted a pointer to an integer, which is ANSI/ISO C says is
	% implementation-defined.  Hmmph.
	%
	% So now we output it as
	%
	%	static const Word * mercury_const_...[] = { (Word *)... };
	%
	% if the constant refers to any code addresses.
	% We output the original format if possible, since we want it
	% to go in rdata if it can, because rdata is shared.
	% References to other static consts should be resolved at compile time,
	% not link time, so should not cause problems.
	%
output_rval_decls(create(_Tag, ArgVals, Label)) -->
	output_cons_arg_decls(ArgVals),
	{ exprn_aux__maybe_rval_list_code_addrs(ArgVals, CodeAddrs) },
	( { CodeAddrs = [] } ->
		io__write_string("static const Word mercury_const_"),
		io__write_int(Label),
		io__write_string("[] = {\n\t\t"),
		output_cons_args(ArgVals, no),
		io__write_string("};\n\t  ")
	;
		io__write_string("static const Word * mercury_const_"),
		io__write_int(Label),
		io__write_string("[] = {\n\t\t"),
		output_cons_args(ArgVals, yes),
		io__write_string("};\n\t  ")
	).

:- pred output_cons_arg_decls(list(maybe(rval)), io__state, io__state).
:- mode output_cons_arg_decls(in, di, uo) is det.

output_cons_arg_decls([]) --> [].
output_cons_arg_decls([Arg | Args]) -->
	( { Arg = yes(Rval) } ->
		output_rval_decls(Rval)
	;
		[]
	),
	output_cons_arg_decls(Args).

:- pred output_cons_args(list(maybe(rval)), bool, io__state, io__state).
:- mode output_cons_args(in, in, di, uo) is det.
% 	output_cons_args(Args, CastToPointer):
%		output the arguments;
%		if CastToPointer is yes, then cast them all to `(Word *)'.

output_cons_args([], _) --> [].
output_cons_args([Arg | Args], CastToPointer) -->
	( { Arg = yes(Rval) } ->
		( { CastToPointer = yes } ->
			io__write_string("(Word *) ")
		;
			[]
		),
		output_rval(Rval)
	;
		% `Arg = no' means the argument is uninitialized,
		% but that would mean the term isn't ground
		{ error("output_cons_args: missing argument") }
	),
	( { Args \= [] } ->
		io__write_string(",\n\t\t"),
		output_cons_args(Args, CastToPointer)
	;
		io__write_string("\n\t  ")
	).

:- pred output_lval_decls(lval, io__state, io__state).
:- mode output_lval_decls(in, di, uo) is det.

output_lval_decls(field(_, Rval, FieldNum)) -->
	output_rval_decls(Rval),
	output_rval_decls(FieldNum).
output_lval_decls(reg(_)) --> [].
output_lval_decls(stackvar(_)) --> [].
output_lval_decls(framevar(_)) --> [].
output_lval_decls(succip) --> [].
output_lval_decls(maxfr) --> [].
output_lval_decls(curfr) --> [].
output_lval_decls(succfr(Rval)) -->
	output_rval_decls(Rval).
output_lval_decls(prevfr(Rval)) -->
	output_rval_decls(Rval).
output_lval_decls(redoip(Rval)) -->
	output_rval_decls(Rval).
output_lval_decls(hp) --> [].
output_lval_decls(sp) --> [].
output_lval_decls(lvar(_)) --> [].
output_lval_decls(temp(_)) --> [].

:- pred output_code_addr_decls(code_addr, io__state, io__state).
:- mode output_code_addr_decls(in, di, uo) is det.

output_code_addr_decls(succip) --> [].
output_code_addr_decls(do_succeed(_)) --> [].
output_code_addr_decls(do_fail) -->
	{ use_macro_for_redo_fail(UseMacro) },
	(
		{ UseMacro = yes }
	;
		{ UseMacro = no },
		io__write_string("Declare_entry("),
		io__write_string("do_fail"),
		io__write_string(");\n\t  ")
	).
output_code_addr_decls(do_redo) -->
	{ use_macro_for_redo_fail(UseMacro) },
	(
		{ UseMacro = yes }
	;
		{ UseMacro = no },
		io__write_string("Declare_entry("),
		io__write_string("do_redo"),
		io__write_string(");\n\t  ")
	).
output_code_addr_decls(label(_)) --> [].
output_code_addr_decls(imported(ProcLabel)) -->
	io__write_string("Declare_entry("),
	output_proc_label(ProcLabel),
	io__write_string(");\n\t  ").

:- pred maybe_output_update_prof_counter(label, io__state, io__state).
:- mode maybe_output_update_prof_counter(in, in, out) is det.

maybe_output_update_prof_counter(Label) -->
	(
		{ Label = local(ProcLabel, _, exported) }
	->
		{ Label2 = exported(ProcLabel) },
		io__write_string("\n\tupdate_prof_current_proc(LABEL("),
		output_label(Label2),
		io__write_string("));\n")
	;
		{ Label = local(ProcLabel, _, local) }
	->
		{ Label2 = local(ProcLabel) },
		io__write_string("\n\tupdate_prof_current_proc(LABEL("),
		output_label(Label2),
		io__write_string("));\n")
	;
		[]
	).

:- pred output_goto(code_addr, code_addr, io__state, io__state).
:- mode output_goto(in, in, di, uo) is det.

	% Note that we do some optimization here:
	% instead of always outputting `GOTO(<label>)', we
	% output different things for each different kind of label.

output_goto(succip, _) -->
	io__write_string("proceed();").
output_goto(do_succeed(Last), _) -->
	(
		{ Last = no },
		io__write_string("succeed();")
	;
		{ Last = yes },
		io__write_string("succeed_discard();")
	).
output_goto(do_fail, _) -->
	{ use_macro_for_redo_fail(UseMacro) },
	(
		{ UseMacro = yes },
		io__write_string("fail();")
	;
		{ UseMacro = no },
		io__write_string("GOTO_LABEL(do_fail);")
	).
output_goto(do_redo, _) -->
	{ use_macro_for_redo_fail(UseMacro) },
	(
		{ UseMacro = yes },
		io__write_string("redo();")
	;
		{ UseMacro = no },
		io__write_string("GOTO_LABEL(do_redo);")
	).
output_goto(imported(ProcLabel), CallerAddr) -->
	io__write_string("tailcall(ENTRY("),
	output_proc_label(ProcLabel),
	io__write_string("),\n\t\t"),
	output_code_addr(CallerAddr),
	io__write_string(");").
output_goto(label(Label), CallerAddr) -->
	(
		{ Label = local(_) ; Label = exported(_) }
	->
		io__write_string("localtailcall("),
		output_label(Label),
		io__write_string(",\n\t\t"),
		output_code_addr(CallerAddr),
		io__write_string(");")
	;
		{ Label = local(_,_,_) }
	->
		io__write_string("GOTO_LABEL("),
		output_label(Label),
		io__write_string(");")
	;
		% just in case - this will always work,
		% but shouldn't be needed
		io__write_string("GOTO(LABEL("),
		output_label(Label),
		io__write_string("));")
	).

	% Note that we also do some optimization here by
	% outputting `localcall' rather than `call' for
	% calls to local labels.

:- pred output_call(code_addr, code_addr, code_addr, io__state, io__state).
:- mode output_call(in, in, in, di, uo) is det.

output_call(Target, Continuation, CallerAddress) -->
	( { Target = label(Label) } ->
		io__write_string("localcall("),
		output_label(Label),
		io__write_string(",\n\t\t"),
		output_code_addr(Continuation),
		io__write_string(",\n\t\t"),
		output_code_addr(CallerAddress),
		io__write_string(");")
	;
		io__write_string("call("),
		output_code_addr(Target),
		io__write_string(",\n\t\t"),
		output_code_addr(Continuation),
		io__write_string(",\n\t\t"),
		output_code_addr(CallerAddress),
		io__write_string(");")
	).

:- pred output_call_closure(code_model, code_addr, io__state, io__state).
:- mode output_call_closure(in, in, di, uo) is det.

output_call_closure(CodeModel, Continuation) -->
	(
		{ CodeModel = model_det },
		io__write_string("call_det_closure("),
		output_code_addr(Continuation),
		io__write_string(");")
	;
		{ CodeModel = model_semi },
		io__write_string("call_semidet_closure("),
		output_code_addr(Continuation),
		io__write_string(");")
	;
		{ CodeModel = model_non },
		io__write_string("call_nondet_closure("),
		output_code_addr(Continuation),
		io__write_string(");")
	).

:- pred output_code_addr(code_addr, io__state, io__state).
:- mode output_code_addr(in, di, uo) is det.

output_code_addr(succip) -->
	io__write_string("succip").
output_code_addr(do_succeed(Last)) -->
	(
		{ Last = no },
		io__write_string("ENTRY(do_succeed)")
	;
		{ Last = yes },
		io__write_string("ENTRY(do_last_succeed)")
	).
output_code_addr(do_fail) -->
	io__write_string("ENTRY(do_fail)").
output_code_addr(do_redo) -->
	io__write_string("ENTRY(do_redo)").
output_code_addr(label(Label)) -->
	io__write_string("LABEL("),
	output_label(Label),
	io__write_string(")").
output_code_addr(imported(ProcLabel)) -->
	io__write_string("ENTRY("),
	output_proc_label(ProcLabel),
	io__write_string(")").

:- pred output_label_list(list(label), io__state, io__state).
:- mode output_label_list(in, di, uo) is det.

output_label_list([]) --> [].
output_label_list([Label | Labels]) -->
	io__write_string("LABEL("),
	output_label(Label),
	io__write_string(")"),
	output_label_list_2(Labels).

:- pred output_label_list_2(list(label), io__state, io__state).
:- mode output_label_list_2(in, di, uo) is det.

output_label_list_2([]) --> [].
output_label_list_2([Label | Labels]) -->
	io__write_string(" AND\n\t\t"),
	io__write_string("LABEL("),
	output_label(Label),
	io__write_string(")"),
	output_label_list_2(Labels).

:- pred output_label_defn(label, io__state, io__state).
:- mode output_label_defn(in, di, uo) is det.

output_label_defn(exported(ProcLabel)) -->
	io__write_string("Define_entry("),
	output_proc_label(ProcLabel),
	io__write_string(");").
output_label_defn(local(ProcLabel)) -->
	globals__io_lookup_int_option(procs_per_c_function, ProcsPerFunc),
	% if we are splitting procs between functions, then
	% every procedure could be referred to by a procedure
	% in a different function, so don't make them local
	( { ProcsPerFunc = 0 } ->
		io__write_string("Define_local("),
		output_proc_label(ProcLabel),
		io__write_string("_l);")	% l for "local".
	;
		io__write_string("Define_entry("),
		output_proc_label(ProcLabel),
		io__write_string(");")
	).
output_label_defn(local(ProcLabel, Num, _)) -->
	io__write_string("Define_label("),
	output_proc_label(ProcLabel),
	io__write_string("_i"),		% i for "internal" (not Intel ;-)
	io__write_int(Num),
	io__write_string(");").

% Note that the suffixes _l etc. used to be interpreted by mod2c,
% which generated different code depending on the suffix.

output_label(exported(ProcLabel)) -->
	output_proc_label(ProcLabel).
output_label(local(ProcLabel)) -->
	output_proc_label(ProcLabel),
	globals__io_lookup_int_option(procs_per_c_function, ProcsPerFunc),
	( { ProcsPerFunc = 0 } ->
		io__write_string("_l")		% l for "local".
	;
		% if we are splitting procs between functions, then
		% every procedure could be referred to by a procedure
		% in a different function, so don't make them local
		[]
	).
output_label(local(ProcLabel, Num, _)) -->
	output_proc_label(ProcLabel),
	io__write_string("_i"),		% i for "internal" (not Intel ;-)
	io__write_int(Num).

:- pred output_proc_label(proc_label, io__state, io__state).
:- mode output_proc_label(in, di, uo) is det.

	% XXX we need to do something with the module name.

output_proc_label(proc(_Module, Pred0, Arity, ModeNum0)) -->
	output_label_prefix,
	%%% io__write_string(Module),
	{ llds__name_mangle(Pred0, Pred) },
	io__write_string(Pred),
	io__write_string("_"),
	io__write_int(Arity),
	io__write_string("_"),
	{ ModeNum is ModeNum0 mod 10000 },	% strip off the priority
	io__write_int(ModeNum).

output_proc_label(special_proc(_Module, PredName, TypeName, TypeArity,
				ModeNum0)) -->
	output_label_prefix,
	%%% io__write_string(Module),
	io__write_string(PredName),
	io__write_string("_"),
	io__write_string(TypeName),
	io__write_string("_"),
	io__write_int(TypeArity),
	io__write_string("_"),
	{ ModeNum is ModeNum0 mod 10000 },	% strip off the priority
	io__write_int(ModeNum).

	% To ensure that Mercury labels don't clash with C symbols, we
	% prefix them with `mercury__'.

:- pred output_label_prefix(io__state, io__state).
:- mode output_label_prefix(di, uo) is det.

output_label_prefix -->
	io__write_string("mercury"),
	io__write_string("__").

:- pred output_reg(reg, io__state, io__state).
:- mode output_reg(in, di, uo) is det.

output_reg(r(N)) -->
	( { N > 32 } ->
		io__write_string("r("),
		io__write_int(N),
		io__write_string(")")
	;
		io__write_string("r"),
		io__write_int(N)
	).
output_reg(f(_)) -->
	{ error("Floating point registers not implemented") }.

:- pred output_tag(tag, io__state, io__state).
:- mode output_tag(in, di, uo) is det.

output_tag(Tag) -->
	io__write_string("mktag("),
	io__write_int(Tag),
	io__write_string(")").

:- pred output_rval(rval, io__state, io__state).
:- mode output_rval(in, di, uo) is det.

output_rval(const(Const)) -->
	output_rval_const(Const).
output_rval(unop(UnaryOp, Exprn)) -->
	output_unary_op(UnaryOp),
	io__write_string("("),
	output_rval(Exprn),
	io__write_string(")").
output_rval(binop(Op, X, Y)) -->
	(
		{ Op = array_index }
	->
		io__write_string("((Word *)"),
		output_rval(X),
		io__write_string(")["),
		output_rval(Y),
		io__write_string("]")
	;
		{ llds__string_op(Op, OpStr) }
	->
		io__write_string("(strcmp((char *)"),
		output_rval(X),
		io__write_string(", (char *)"),
		output_rval(Y),
		io__write_string(")"),
		io__write_string(" "),
		io__write_string(OpStr),
		io__write_string("0)")
	;
		{ llds__float_compare_op(Op, OpStr) }
	->
		io__write_string("(word_to_float("),
		output_rval(X),
		io__write_string(") "),
		io__write_string(OpStr),
		io__write_string(" word_to_float("),
		output_rval(Y),
		io__write_string("))")
	;
		{ llds__float_op(Op, OpStr) }
	->
		io__write_string("float_to_word(word_to_float("),
		output_rval(X),
		io__write_string(") "),
		io__write_string(OpStr),
		io__write_string(" word_to_float("),
		output_rval(Y),
		io__write_string("))")
	;
		{ Op = (+) },
		{ Y = const(int_const(C)) },
		{ C < 0 }
	->
		{ NewOp = (-) },
		{ NewC is 0 - C },
		{ NewY = const(int_const(NewC)) },
		io__write_string("("),
		output_rval(X),
		io__write_string(" "),
		output_binary_op(NewOp),
		io__write_string(" "),
		output_rval(NewY),
		io__write_string(")")
	;
		io__write_string("("),
		output_rval(X),
		io__write_string(" "),
		output_binary_op(Op),
		io__write_string(" "),
		output_rval(Y),
		io__write_string(")")
	).
output_rval(mkword(Tag, Exprn)) -->
	io__write_string("(Integer) mkword("),
	output_tag(Tag),
	io__write_string(", "),
	output_rval(Exprn),
	io__write_string(")").
output_rval(lval(Lval)) -->
	output_rval_lval(Lval).
output_rval(create(Tag, _Args, LabelNum)) -->
		% emit a reference to the static constant which we
		% declared in output_rval_decls.
	io__write_string("mkword(mktag("),
	io__write_int(Tag),
	io__write_string("), "),
	io__write_string("mercury_const_"),
	io__write_int(LabelNum),
	io__write_string(")").
output_rval(var(_)) -->
	{ error("Cannot output a var(_) expression in code") }.

:- pred output_unary_op(unary_op, io__state, io__state).
:- mode output_unary_op(in, di, uo) is det.

output_unary_op(mktag) -->
	io__write_string("mktag").
output_unary_op(tag) -->
	io__write_string("tag").
output_unary_op(unmktag) -->
	io__write_string("unmktag").
output_unary_op(mkbody) -->
	io__write_string("mkbody").
output_unary_op(body) -->
	io__write_string("body").
output_unary_op(unmkbody) -->
	io__write_string("unmkbody").
output_unary_op(hash_string) -->
	io__write_string("hash_string").
output_unary_op(bitwise_complement) -->
	io__write_string("~").
output_unary_op(not) -->
	io__write_string("!").
output_unary_op(cast_to_unsigned) -->
	io__write_string("(unsigned)").

:- pred llds__string_op(binary_op, string).
:- mode llds__string_op(in, out) is semidet.

llds__string_op(str_eq, "==").
llds__string_op(str_ne, "!=").
llds__string_op(str_le, "<=").
llds__string_op(str_ge, ">=").
llds__string_op(str_lt, "<").
llds__string_op(str_gt, ">").

:- pred llds__float_op(binary_op, string).
:- mode llds__float_op(in, out) is semidet.

llds__float_op(float_plus, "+").
llds__float_op(float_minus, "-").
llds__float_op(float_times, "*").
llds__float_op(float_divide, "/").

:- pred llds__float_compare_op(binary_op, string).
:- mode llds__float_compare_op(in, out) is semidet.

llds__float_compare_op(float_eq, "==").
llds__float_compare_op(float_ne, "!=").
llds__float_compare_op(float_le, "<=").
llds__float_compare_op(float_ge, ">=").
llds__float_compare_op(float_lt, "<").
llds__float_compare_op(float_gt, ">").

:- pred output_rval_const(rval_const, io__state, io__state).
:- mode output_rval_const(in, di, uo) is det.

output_rval_const(int_const(N)) -->
	io__write_int(N).
output_rval_const(float_const(Float)) -->
	io__write_string("float_const("),
	io__write_float(Float),
	io__write_string(")").
output_rval_const(string_const(String)) -->
	io__write_string("string_const("""),
	output_c_quoted_string(String),
	{ string__length(String, StringLength) },
	io__write_string(""", "),
	io__write_int(StringLength),
	io__write_string(")").
output_rval_const(true) -->
	io__write_string("TRUE").
output_rval_const(false) -->
	io__write_string("FALSE").
output_rval_const(address_const(CodeAddress)) -->
	io__write_string("(Integer) "),
	output_code_addr(CodeAddress).

:- pred output_lval(lval, io__state, io__state).
:- mode output_lval(in, di, uo) is det.

output_lval(reg(R)) -->
	output_reg(R).
output_lval(stackvar(N)) -->
	{ (N < 0) ->
		error("stack var out of range")
	;
		true
	},
	io__write_string("detstackvar("),
	io__write_int(N),
	io__write_string(")").
output_lval(framevar(N)) -->
	{ (N < 0) ->
		error("frame var out of range")
	;
		true
	},
	io__write_string("framevar("),
	io__write_int(N),
	io__write_string(")").
output_lval(succip) -->
	io__write_string("LVALUE_CAST(Word,succip)").
output_lval(sp) -->
	io__write_string("LVALUE_CAST(Word,sp)").
output_lval(hp) -->
	io__write_string("LVALUE_CAST(Word,hp)").
output_lval(maxfr) -->
	io__write_string("LVALUE_CAST(Word,maxfr)").
output_lval(curfr) -->
	io__write_string("LVALUE_CAST(Word,curfr)").
output_lval(succfr(Rval)) -->
	io__write_string("LVALUE_CAST(Word,bt_succfr("),
	output_rval(Rval),
	io__write_string("))").
output_lval(prevfr(Rval)) -->
	io__write_string("LVALUE_CAST(Word,bt_prevfr("),
	output_rval(Rval),
	io__write_string("))").
output_lval(redoip(Rval)) -->
	io__write_string("LVALUE_CAST(Word,bt_redoip("),
	output_rval(Rval),
	io__write_string("))").
output_lval(field(Tag, Rval, FieldNum)) -->
	io__write_string("field("),
	output_tag(Tag),
	io__write_string(", "),
	output_rval(Rval),
	io__write_string(", "),
	output_rval(FieldNum),
	io__write_string(")").
output_lval(lvar(_)) -->
	{ error("Illegal to output an lvar") }.
output_lval(temp(N)) -->
	io__write_string("temp"),
	io__write_int(N).

% output_rval_lval is the same as output_lval,
% except that the result is cast to (Integer).

:- pred output_rval_lval(lval, io__state, io__state).
:- mode output_rval_lval(in, di, uo) is det.

output_rval_lval(reg(R)) -->
	io__write_string("(Integer) "),
	output_reg(R).
output_rval_lval(stackvar(N)) -->
	{ (N < 0) ->
		error("stack var out of range")
	;
		true
	},
	io__write_string("(Integer) detstackvar("),
	io__write_int(N),
	io__write_string(")").
output_rval_lval(framevar(N)) -->
	{ (N < 0) ->
		error("nondet stack var out of range")
	;
		true
	},
	io__write_string("(Integer) framevar("),
	io__write_int(N),
	io__write_string(")").
output_rval_lval(succip) -->
	io__write_string("(Integer) succip").
output_rval_lval(sp) -->
	io__write_string("(Integer) sp").
output_rval_lval(hp) -->
	io__write_string("(Integer) hp").
output_rval_lval(maxfr) -->
	io__write_string("(Integer) maxfr").
output_rval_lval(curfr) -->
	io__write_string("(Integer) curfr").
output_rval_lval(succfr(Rval)) -->
	io__write_string("(Integer) bt_succfr("),
	output_rval(Rval),
	io__write_string(")").
output_rval_lval(prevfr(Rval)) -->
	io__write_string("(Integer) bt_prevfr("),
	output_rval(Rval),
	io__write_string(")").
output_rval_lval(redoip(Rval)) -->
	io__write_string("(Integer) bt_redoip("),
	output_rval(Rval),
	io__write_string(")").
output_rval_lval(field(Tag, Rval, FieldNum)) -->
	io__write_string("(Integer) field("),
	output_tag(Tag),
	io__write_string(", "),
	output_rval(Rval),
	io__write_string(", "),
	output_rval(FieldNum),
	io__write_string(")").
output_rval_lval(lvar(_)) -->
	{ error("Illegal to output an lvar") }.
output_rval_lval(temp(N)) -->
	io__write_string("(Integer) temp"),
	io__write_int(N).

%-----------------------------------------------------------------------------%

:- pred output_c_quoted_string(string, io__state, io__state).
:- mode output_c_quoted_string(in, di, uo) is det.

output_c_quoted_string(S0) -->
	( { string__first_char(S0, Char, S1) } ->
		( { quote_c_char(Char, QuoteChar) } ->
			io__write_char('\\'),
			io__write_char(QuoteChar)
		;
			io__write_char(Char)
		),
		output_c_quoted_string(S1)
	;
		[]
	).

:- pred quote_c_char(character, character).
:- mode quote_c_char(in, out) is semidet.

quote_c_char('"', '"').
quote_c_char('\\', '\\').
quote_c_char('\n', 'n').
quote_c_char('\t', 't').
quote_c_char('\b', 'b').

%-----------------------------------------------------------------------------%

:- pred output_binary_op(binary_op, io__state, io__state).
:- mode output_binary_op(in, di, uo) is det.

output_binary_op(Op) -->
	{ llds__binary_op_to_string(Op, String) },
	io__write_string(String).

llds__binary_op_to_string(+, "+").
llds__binary_op_to_string(-, "-").
llds__binary_op_to_string(*, "*").
llds__binary_op_to_string(/, "/").
llds__binary_op_to_string(<<, "<<").
llds__binary_op_to_string(>>, ">>").
llds__binary_op_to_string(&, "&").
llds__binary_op_to_string('|', "|").
llds__binary_op_to_string(^, "^").
llds__binary_op_to_string(mod, "%").
llds__binary_op_to_string(eq, "==").
llds__binary_op_to_string(ne, "!=").
llds__binary_op_to_string(and, "&&").
llds__binary_op_to_string(or, "||").
llds__binary_op_to_string(<, "<").
llds__binary_op_to_string(>, ">").
llds__binary_op_to_string(<=, "<=").
llds__binary_op_to_string(>=, ">=").
	% The following is just for debugging purposes -
	% string operators are not output as `str_eq', etc.
llds__binary_op_to_string(array_index, "array_index").
llds__binary_op_to_string(str_eq, "str_eq").
llds__binary_op_to_string(str_ne, "str_ne").
llds__binary_op_to_string(str_lt, "str_lt").
llds__binary_op_to_string(str_gt, "str_gt").
llds__binary_op_to_string(str_le, "str_le").
llds__binary_op_to_string(str_ge, "str_ge").
llds__binary_op_to_string(float_eq, "float_eq").
llds__binary_op_to_string(float_ne, "float_ne").
llds__binary_op_to_string(float_lt, "float_lt").
llds__binary_op_to_string(float_gt, "float_gt").
llds__binary_op_to_string(float_le, "float_le").
llds__binary_op_to_string(float_ge, "float_ge").
llds__binary_op_to_string(float_plus, "float_plus").
llds__binary_op_to_string(float_minus, "float_minus").
llds__binary_op_to_string(float_times, "float_times").
llds__binary_op_to_string(float_divide, "float_divide").

%-----------------------------------------------------------------------------%

:- pred clause_num_to_string(int::in, string::out) is det.

clause_num_to_string(N, Str) :-
	( clause_num_to_string_2(N, Str0) ->
		Str = Str0
	;
		error("clause_num_to_string failed")
	).

:- pred clause_num_to_string_2(int::in, string::out) is semidet.

clause_num_to_string_2(N, Str) :-
	(
		N < 26
	->
		int_to_letter(N, Str)
	;
		N_Low is N mod 26,
		N_High is N // 26,
		int_to_letter(N_Low, L),
		clause_num_to_string(N_High, S),
		string__append(S, L, Str)
	).

:- pred int_to_letter(int, string).
:- mode int_to_letter(in, out) is semidet.

	% This code is boring, but portable - it works even for EBCDIC ;-)

int_to_letter(0, "a").
int_to_letter(1, "b").
int_to_letter(2, "c").
int_to_letter(3, "d").
int_to_letter(4, "e").
int_to_letter(5, "f").
int_to_letter(6, "g").
int_to_letter(7, "h").
int_to_letter(8, "i").
int_to_letter(9, "j").
int_to_letter(10, "k").
int_to_letter(11, "l").
int_to_letter(12, "m").
int_to_letter(13, "n").
int_to_letter(14, "o").
int_to_letter(15, "p").
int_to_letter(16, "q").
int_to_letter(17, "r").
int_to_letter(18, "s").
int_to_letter(19, "t").
int_to_letter(20, "u").
int_to_letter(21, "v").
int_to_letter(22, "w").
int_to_letter(23, "x").
int_to_letter(24, "y").
int_to_letter(25, "z").

llds__lval_to_string(framevar(N), Description) :-
	string__int_to_string(N, N_String),
	string__append("framevar(", N_String, Tmp),
	string__append(Tmp, ")", Description).
llds__lval_to_string(stackvar(N), Description) :-
	string__int_to_string(N, N_String),
	string__append("stackvar(", N_String, Tmp),
	string__append(Tmp, ")", Description).
llds__lval_to_string(reg(Reg), Description) :-
	llds__reg_to_string(Reg, Reg_String),
	string__append("reg(", Reg_String, Tmp),
	string__append(Tmp, ")", Description).

:- pred llds__reg_to_string(reg, string).
:- mode llds__reg_to_string(in, out) is det.

llds__reg_to_string(r(N), Description) :-
	string__int_to_string(N, N_String),
	string__append("r(", N_String, Tmp),
	string__append(Tmp, ")", Description).
llds__reg_to_string(f(N), Description) :-
	string__int_to_string(N, N_String),
	string__append("f(", N_String, Tmp),
	string__append(Tmp, ")", Description).

%-----------------------------------------------------------------------------%

	% Convert a Mercury predicate name into something that can form
	% part of a C identifier.  This predicate is necessary because
	% quoted names such as 'name with embedded spaces' are valid
	% predicate names in Mercury.

:- pred llds__name_mangle(string, string).
:- mode llds__name_mangle(in, out) is det.

llds__name_mangle(Name, MangledName) :-
	(
		string__is_alnum_or_underscore(Name)
	->
		% any names that start with `f_' are changed so that
		% they start with `f__', so that we can use names starting
		% with `f_' (followed by anything except an underscore)
		% without fear of name collisions
		(
			string__append("f_", Suffix, Name)
		->
			string__append("f__", Suffix, MangledName)
		;
			MangledName = Name
		)
	;
		llds__convert_to_valid_c_identifier(Name, MangledName)
	).


:- pred llds__convert_to_valid_c_identifier(string, string).
:- mode llds__convert_to_valid_c_identifier(in, out) is det.

llds__convert_to_valid_c_identifier(String, Name) :-	
	(
		llds__name_conversion_table(String, Name0)
	->
		Name = Name0
	;
		llds__convert_to_valid_c_identifier_2(String, Name0),
		string__append("f", Name0, Name)
	).

	% A table used to convert Mercury functors into
	% C identifiers.  Feel free to add any new translations you want.
	% The C identifiers should start with "f_",
	% to avoid introducing name clashes.
	% If the functor name is not found in the table, then
	% we use a fall-back method which produces ugly names.

:- pred llds__name_conversion_table(string, string).
:- mode llds__name_conversion_table(in, out) is semidet.

llds__name_conversion_table("\\=", "f_not_equal").
llds__name_conversion_table(">=", "f_greater_or_equal").
llds__name_conversion_table("=<", "f_less_or_equal").
llds__name_conversion_table("=", "f_equal").
llds__name_conversion_table("<", "f_less_than").
llds__name_conversion_table(">", "f_greater_than").
llds__name_conversion_table("-", "f_minus").
llds__name_conversion_table("+", "f_plus").
llds__name_conversion_table("*", "f_times").
llds__name_conversion_table("/", "f_slash").
llds__name_conversion_table(",", "f_comma").
llds__name_conversion_table(";", "f_semicolon").

	% This is the fall-back method.
	% Given a string, produce a C identifier
	% for that string by concatenating the decimal
	% expansions of the character codes in the string,
	% separated by underlines.
	% The C identifier will start with "f_"; this predicate
	% constructs everything except the initial "f".
	%
	% For example, given the input "\n\t" we return "_10_8".

:- pred llds__convert_to_valid_c_identifier_2(string, string).
:- mode llds__convert_to_valid_c_identifier_2(in, out) is det.

llds__convert_to_valid_c_identifier_2(String, Name) :-	
	(
		string__first_char(String, Char, Rest)
	->
		char_to_int(Char, Code),
		string__int_to_string(Code, CodeString),
		string__append("_", CodeString, ThisCharString),
		llds__convert_to_valid_c_identifier_2(Rest, Name0),
		string__append(ThisCharString, Name0, Name)
	;
		% String is the empty string
		Name = String
	).

%-----------------------------------------------------------------------------%

:- pred gather_labels(list(c_procedure), list(label)).
:- mode gather_labels(in, out) is det.

gather_labels(Procs, Labels) :-
	gather_labels_2(Procs, [], Labels1),
	list__reverse(Labels1, Labels).

:- pred gather_labels_2(list(c_procedure), list(label), list(label)).
:- mode gather_labels_2(in, di, uo) is det.

gather_labels_2([], Labels, Labels).
gather_labels_2([c_procedure(_, _, _, Instrs) | Procs], Labels0, Labels) :-
	gather_labels_from_instrs(Instrs, Labels0, Labels1),
	gather_labels_2(Procs, Labels1, Labels).

:- pred gather_labels_from_instrs(list(instruction), list(label), list(label)).
:- mode gather_labels_from_instrs(in, di, uo) is det.

gather_labels_from_instrs([], Labels, Labels).
gather_labels_from_instrs([Instr | Instrs], Labels0, Labels) :-
	( Instr = label(Label) - _ ->
		Labels1 = [Label | Labels0]
	;
		Labels1 = Labels0
	),
	gather_labels_from_instrs(Instrs, Labels1, Labels).

:- pred use_macro_for_redo_fail(bool).
:- mode use_macro_for_redo_fail(out) is det.

% this ought to be a compiler option...

use_macro_for_redo_fail(yes).

:- end_module llds.

%-----------------------------------------------------------------------------%
