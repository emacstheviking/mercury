%-----------------------------------------------------------------------------%
% Copyright (C) 2002 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: make.util.m
% Main author: stayl
%
% Assorted predicates used to implement `mmc --make'.
%-----------------------------------------------------------------------------%
:- module make__util.

:- interface.

	%
	% Versions of foldl which stop if the supplied predicate returns `no'
	% for any element of the list.
	%

	% foldl2_pred_with_status(T, Succeeded, Info0, Info).
:- type foldl2_pred_with_status(T, Info, IO) ==
				pred(T, bool, Info, Info, IO, IO).
:- inst foldl2_pred_with_status == (pred(in, out, in, out, di, uo) is det).

	% foldl2_maybe_stop_at_error(KeepGoing, P, List,
	%	Succeeded, Info0, Info).
:- pred foldl2_maybe_stop_at_error(bool::in,
	foldl2_pred_with_status(T, Info, IO)::in(foldl2_pred_with_status),
	list(T)::in, bool::out, Info::in, Info::out, IO::di, IO::uo) is det.

	% foldl3_pred_with_status(T, Succeeded, Acc0, Acc, Info0, Info).
:- type foldl3_pred_with_status(T, Acc, Info, IO) ==
		pred(T, bool, Acc, Acc, Info, Info, IO, IO).
:- inst foldl3_pred_with_status ==
		(pred(in, out, in, out, in, out, di, uo) is det).

	% foldl3_maybe_stop_at_error(KeepGoing, P, List,
	%	Succeeded, Acc0, Acc, Info0, Info).
:- pred foldl3_maybe_stop_at_error(bool::in,
	foldl3_pred_with_status(T, Acc, Info, IO)::in(foldl3_pred_with_status),
	list(T)::in, bool::out, Acc::in, Acc::out, Info::in, Info::out,
	IO::di, IO::uo) is det.

%-----------------------------------------------------------------------------%
	% Code to handle cleaning up when a signal is received.

:- type build0 == pred(bool, make_info, make_info, io__state, io__state).
:- inst build0 == (pred(out, in, out, di, uo) is det).

:- type post_signal_cleanup ==
		pred(make_info, make_info, io__state, io__state).
:- inst post_signal_cleanup == (pred(in, out, di, uo) is det).

	% build_with_check_for_interrupt(Build, Cleanup,
	%	Succeeded, Info0, Info)
	%
	% Apply `Build' with signal handlers installed to check for signals
	% which would normally kill the process. If a signal occurs call
	% `Cleanup', then restore signal handlers to their defaults and
	% reraise the signal to kill the current process.
	% An action being performed in a child process by
	% call_in_forked_process will be killed if a fatal signal
	% (SIGINT, SIGTERM, SIGHUP or SIGQUIT) is received by the
	% current process.
	% An action being performed within the current process or by
	% system() will run to completion, with the interrupt being taken
	% immediately afterwards.
:- pred build_with_check_for_interrupt(build0::in(build0),
	post_signal_cleanup::in(post_signal_cleanup),
	bool::out, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- type build(T) == pred(T, bool, make_info, make_info, io__state, io__state).
:- inst build == (pred(in, out, in, out, di, uo) is det).

	% Perform the given closure after updating the option_table in
	% the globals in the io__state to contain the module-specific
	% options for the specified module.
:- pred build_with_module_options(module_name::in,
	list(string)::in, build(list(string))::in(build), bool::out,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% Perform the given closure with an output stream created
	% to append to the error file for the given module.
:- pred build_with_output_redirect(module_name::in,
	build(io__output_stream)::in(build), bool::out,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% Produce an output stream which writes to the error file
	% for the given module.
:- pred redirect_output(module_name::in, maybe(io__output_stream)::out,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% Close the module error output stream.
:- pred unredirect_output(module_name::in, io__output_stream::in,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- type build2(T, U) == pred(T, U, bool, make_info, make_info,
				io__state, io__state).
:- inst build2 == (pred(in, in, out, in, out, di, uo) is det).

:- pred build_with_module_options_and_output_redirect(module_name::in,
	list(string)::in, build2(list(string), io__output_stream)::in(build2),
	bool::out, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- type io_pred == pred(bool, io__state, io__state).
:- inst io_pred == (pred(out, di, uo) is det).

	% call_in_forked_process(P, AltP, Succeeded)
	%
	% Execute `P' in a separate process.
	%
	% We prefer to use fork() rather than system() because
	% that will avoid shell and Mercury runtime startup overhead.
	% Interrupt handling will also work better (system() on Linux
	% ignores SIGINT).
	%
	% If fork() is not supported on the current architecture,
	% `AltP' will be called instead in the current process.
:- pred call_in_forked_process(io_pred::in(io_pred), io_pred::in(io_pred),
	bool::out, io__state::di, io__state::uo) is det.

	% As above, but if fork() is not available, just call the
	% predicate in the current process.
:- pred call_in_forked_process(io_pred::in(io_pred),
	bool::out, io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%
	% Timestamp handling.

	% Find the timestamp updated when a target is produced.
:- pred get_timestamp_file_timestamp(target_file::in,
	maybe_error(timestamp)::out, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

	% Find the timestamp for the given dependency file.
:- pred get_dependency_timestamp(dependency_file::in,
	maybe_error(timestamp)::out, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

	% Find the timestamp for the given target file.
:- pred get_target_timestamp(target_file::in, maybe_error(timestamp)::out,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% Compute a file name for the given target file.
:- pred get_file_name(target_file::in, file_name::out,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% Find the timestamp of the first file matching the given
	% file name in one of the given directories.
:- pred get_file_timestamp(list(dir_name)::in, file_name::in,
	maybe_error(timestamp)::out, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%
	% Remove file a file, deleting the cached timestamp.

	% Remove the target file and the corresponding timestamp file.
:- pred remove_target_file(target_file::in, make_info::in, make_info::out,
	io__state::di, io__state::uo) is det.

	% Remove the target file and the corresponding timestamp file.
:- pred remove_target_file(module_name::in, module_target_type::in,
	make_info::in, make_info::out, io__state::di, io__state::uo) is det.

	% remove_file(ModuleName, Extension, Info0, Info).
:- pred remove_file(module_name::in, string::in, make_info::in, make_info::out,
		io__state::di, io__state::uo) is det.

:- pred remove_file(file_name::in, make_info::in, make_info::out,
		io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%

:- func make_target_list(list(K), V) = assoc_list(K, V).

:- func make_dependency_list(list(module_name), module_target_type) =
		list(dependency_file).

:- func target_extension(globals, module_target_type) = string.
:- mode target_extension(in, in) = out is det.
:- mode target_extension(in, out) = in is nondet.

:- func linked_target_extension(globals, linked_target_type) = string.
:- mode linked_target_extension(in, in) = out is det.
:- mode linked_target_extension(in, out) = in is nondet.

	% Find the extension for the timestamp file for the
	% given target type, if one exists.
:- func timestamp_extension(module_target_type) = string is semidet.

%-----------------------------------------------------------------------------%
	% Debugging, verbose and error messages.

	% Apply the given predicate if `--debug-make' is set.
:- pred debug_msg(pred(io__state, io__state)::(pred(di, uo) is det),
		io__state::di, io__state::uo) is det.

	% Apply the given predicate if `--verbose-make' is set.
:- pred verbose_msg(pred(io__state, io__state)::(pred(di, uo) is det),
		io__state::di, io__state::uo) is det.

	% Write a debugging message relating to a given target file.
:- pred debug_file_msg(target_file::in, string::in,
		io__state::di, io__state::uo) is det.

:- pred write_dependency_file(dependency_file::in,
		io__state::di, io__state::uo) is det.

:- pred write_target_file(target_file::in,
		io__state::di, io__state::uo) is det.

	% Write a message "Making <filename>" if `--verbose-make' is set.
:- pred maybe_make_linked_target_message(file_name::in,
		io__state::di, io__state::uo) is det.

	% Write a message "Making <filename>" if `--verbose-make' is set.
:- pred maybe_make_target_message(target_file::in,
		io__state::di, io__state::uo) is det.

:- pred maybe_make_target_message(io__output_stream::in, target_file::in,
		io__state::di, io__state::uo) is det.

	% Write a message "** Error making <filename>".
:- pred target_file_error(target_file::in,
		io__state::di, io__state::uo) is det.

	% Write a message "** Error making <filename>".
:- pred file_error(file_name::in, io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%
:- implementation.

foldl2_maybe_stop_at_error(KeepGoing, MakeTarget,
		Targets, Success, Info0, Info) -->
	foldl2_maybe_stop_at_error_2(KeepGoing, MakeTarget, Targets,
		yes, Success, Info0, Info).

:- pred foldl2_maybe_stop_at_error_2(bool::in,
	foldl2_pred_with_status(T, Info, IO)::in(foldl2_pred_with_status),
	list(T)::in, bool::in, bool::out, Info::in, Info::out,
	IO::di, IO::uo) is det.

foldl2_maybe_stop_at_error_2(_KeepGoing, _P, [],
		Success, Success, Info, Info) --> [].
foldl2_maybe_stop_at_error_2(KeepGoing, P, [T | Ts],
		Success0, Success, Info0, Info) -->
	P(T, Success1, Info0, Info1),
	( { Success1 = yes ; KeepGoing = yes } ->
		foldl2_maybe_stop_at_error_2(KeepGoing, P, Ts,
			Success0 `and` Success1, Success, Info1, Info)
	;
		{ Success = no },
		{ Info = Info0 }
	).

foldl3_maybe_stop_at_error(KeepGoing, P, Ts, Success,
		Acc0, Acc, Info0, Info) -->
	foldl3_maybe_stop_at_error_2(KeepGoing, P, Ts,
		yes, Success, Acc0, Acc, Info0, Info).

:- pred foldl3_maybe_stop_at_error_2(bool::in,
	foldl3_pred_with_status(T, Acc, Info, IO)::in(foldl3_pred_with_status),
	list(T)::in, bool::in, bool::out, Acc::in, Acc::out,
	Info::in, Info::out, IO::di, IO::uo) is det.

foldl3_maybe_stop_at_error_2(_KeepGoing, _P, [],
		Success, Success, Acc, Acc, Info, Info) --> [].
foldl3_maybe_stop_at_error_2(KeepGoing, P, [T | Ts],
		Success0, Success, Acc0, Acc, Info0, Info) -->
	P(T, Success1, Acc0, Acc1, Info0, Info1),
	( { Success1 = yes ; KeepGoing = yes } ->
		foldl3_maybe_stop_at_error_2(KeepGoing, P, Ts,
			Success0 `and` Success1, Success, Acc1, Acc,
			Info1, Info)
	;
		{ Success = no },
		{ Acc = Acc0 },
		{ Info = Info0 }
	).

%-----------------------------------------------------------------------------%

build_with_check_for_interrupt(Build, Cleanup, Succeeded, Info0, Info) -->
	setup_signal_handlers(MaybeSigIntHandler),
	Build(Succeeded0, Info0, Info1),
	restore_signal_handlers(MaybeSigIntHandler),
	check_for_signal(Signalled, Signal),
	( { Signalled = 1 } ->
		{ Succeeded = no },
		verbose_msg(
			(pred(di, uo) is det -->
				io__write_string("** Received signal "),
				io__write_int(Signal),
				io__write_string(", cleaning up.\n")
			)),
		Cleanup(Info1, Info),

		% The signal handler has been restored to the default,
		% so this should kill us.
		raise_signal(Signal)
	;
		{ Succeeded = Succeeded0 },
		{ Info = Info1 }
	).	

:- type signal_action ---> signal_action(c_pointer).

:- pragma foreign_decl("C",
"
#ifdef MR_HAVE_UNISTD_H
  #include <unistd.h>
#endif

#ifdef MR_HAVE_SYS_TYPES_H
  #include <sys/types.h>
#endif

#ifdef MR_HAVE_SYS_WAIT_H
  #include <sys/wait.h>
#endif

#include <errno.h>

#include ""mercury_signal.h""
#include ""mercury_types.h""
#include ""mercury_heap.h""
#include ""mercury_misc.h""

#if defined(MR_HAVE_FORK) && defined(MR_HAVE_WAIT) && defined(MR_HAVE_KILL)
  #define MC_CAN_FORK 1
#endif

#define MC_SETUP_SIGNAL_HANDLER(sig, handler) \
		MR_setup_signal(sig, (MR_Code *) handler, MR_FALSE,	\
			""mercury_compile: cannot install signal handler"");

	/* Have we received a signal. */
volatile sig_atomic_t MC_signalled;

	/*
	** Which signal did we receive.
	** XXX This assumes a signal number will fit into a sig_atomic_t.
	*/
volatile sig_atomic_t MC_signal_received;

void MC_mercury_compile_signal_handler(int sig);
").

:- pragma foreign_code("C",
"
volatile sig_atomic_t MC_signalled = MR_FALSE;
volatile sig_atomic_t MC_signal_received = 0;

void
MC_mercury_compile_signal_handler(int sig)
{
	MC_signalled = MR_TRUE;
	MC_signal_received = sig;
}
").

:- pred setup_signal_handlers(maybe(signal_action)::out,
		io__state::di, io__state::uo) is det.

setup_signal_handlers(MaybeSigIntHandler) -->
	( { have_signal_handlers(1) } ->
		setup_signal_handlers_2(SigintHandler),
		{ MaybeSigIntHandler = yes(SigintHandler) }
	;
		{ MaybeSigIntHandler = no }
	).

	% Dummy argument to work around bug mixing Mercury and foreign clauses.
:- pred have_signal_handlers(T::unused) is semidet.

have_signal_handlers(_::unused) :- semidet_fail.

:- pragma foreign_proc("C", have_signal_handlers(_T::unused),
		[will_not_call_mercury, promise_pure],
"{
	SUCCESS_INDICATOR = MR_TRUE;
}").

:- pred setup_signal_handlers_2(signal_action::out,
		io__state::di, io__state::uo) is det.

setup_signal_handlers_2(_::out, _::di, _::uo) :-
	error("setup_signal_handlers_2").

:- pragma foreign_proc("C",
		setup_signal_handlers_2(SigintHandler::out, IO0::di, IO::uo),
		[will_not_call_mercury, promise_pure],
"{
	IO = IO0;
	MC_signalled = MR_FALSE;

	MR_incr_hp_msg(SigintHandler,
		MR_bytes_to_words(sizeof(MR_signal_action)),
		MR_PROC_LABEL, ""make.util.signal_action/0"");

	/*
	** mdb sets up a SIGINT handler, so we should restore
	** it after we're done.
	*/
	MR_get_signal_action(SIGINT, (MR_signal_action *) SigintHandler,
		""error getting SIGINT handler"");
	MC_SETUP_SIGNAL_HANDLER(SIGINT, MC_mercury_compile_signal_handler);
	MC_SETUP_SIGNAL_HANDLER(SIGTERM, MC_mercury_compile_signal_handler);
#ifdef SIGHUP
	MC_SETUP_SIGNAL_HANDLER(SIGHUP, MC_mercury_compile_signal_handler);
#endif
#ifdef SIGQUIT
	MC_SETUP_SIGNAL_HANDLER(SIGQUIT, MC_mercury_compile_signal_handler);
#endif
}").

:- pred restore_signal_handlers(maybe(signal_action)::in,
		io__state::di, io__state::uo) is det.

restore_signal_handlers(no) --> [].
restore_signal_handlers(yes(SigintHandler)) -->
	restore_signal_handlers_2(SigintHandler).

:- pred restore_signal_handlers_2(signal_action::in,
		io__state::di, io__state::uo) is det.

restore_signal_handlers_2(_::in, _::di, _::uo) :-
	error("restore_signal_handlers_2").

:- pragma foreign_proc("C",
		restore_signal_handlers_2(SigintHandler::in, IO0::di, IO::uo),
		[will_not_call_mercury, promise_pure],
"{
	IO = IO0;
	MR_set_signal_action(SIGINT, (MR_signal_action *) SigintHandler,
		""error resetting SIGINT handler"");
	MC_SETUP_SIGNAL_HANDLER(SIGTERM, SIG_DFL);
#ifdef SIGHUP
	MC_SETUP_SIGNAL_HANDLER(SIGHUP, SIG_DFL);
#endif
#ifdef SIGQUIT
	MC_SETUP_SIGNAL_HANDLER(SIGQUIT, SIG_DFL);
#endif
}").

:- pred check_for_signal(int::out, int::out,
		io__state::di, io__state::uo) is det.

:- pragma foreign_proc("C",
		check_for_signal(Signalled::out, Signal::out, IO0::di, IO::uo),
		[will_not_call_mercury, promise_pure],
"
	IO = IO0;
	Signalled = (MC_signalled ? 1 : 0);
	Signal = MC_signal_received;
").

:- pred raise_signal(int::in, io__state::di, io__state::uo) is det.

:- pragma foreign_proc("C",
		raise_signal(Signal::in, IO0::di, IO::uo),
		[will_not_call_mercury, promise_pure],
"
	IO = IO0;
	raise(Signal);
").

%-----------------------------------------------------------------------------%

call_in_forked_process(P, Success) -->
	call_in_forked_process(P, P, Success).

call_in_forked_process(P, AltP, Success) -->
	( { can_fork(1) } ->
		debug_msg(io__write_string("call_in_forked_process\n")),
		call_in_forked_process_2(P, ForkStatus, CallStatus),
		{ ForkStatus = 1 ->
			Success = no
		;
			Status = io__handle_system_command_exit_status(
					CallStatus),
			Success = (Status = ok(exited(0)) -> yes ; no)
		},
		debug_msg(io__write_string(
				"finished call_in_forked_process\n"))
	;
		AltP(Success)
	).

	% Dummy argument to work around bug mixing Mercury and foreign clauses.
:- pred can_fork(T::unused) is semidet.

can_fork(_::unused) :- semidet_fail.

:- pragma foreign_proc("C", can_fork(_T::unused),
		[will_not_call_mercury, thread_safe, promise_pure],
"
#ifdef MC_CAN_FORK
	SUCCESS_INDICATOR = MR_TRUE;
#else
	SUCCESS_INDICATOR = MR_FALSE;
#endif
").

:- pred call_in_forked_process_2(io_pred::in(io_pred), int::out, int::out,
		io__state::di, io__state::uo) is det.

call_in_forked_process_2(_::in(io_pred), _::out, _::out, _::di, _::uo) :-
	error("call_in_forked_process_2").

:- pragma foreign_proc("C",
		call_in_forked_process_2(Pred::in(io_pred),
			ForkStatus::out, Status::out, IO0::di, IO::uo),
			[may_call_mercury, promise_pure],
"{
#ifdef MC_CAN_FORK
	pid_t child_pid;

	IO = IO0;
	ForkStatus = 0;
	Status = 0;

	child_pid = fork();
	if (child_pid == -1) {		/* error */
		MR_perror(""error in fork()"");
		ForkStatus = 1;
	} else if (child_pid == 0) {	/* child */
		MR_Integer exit_status;

		MC_call_io_pred(Pred, &exit_status);
		exit(exit_status);
	} else {			/* parent */
		int child_status;
		pid_t wait_status;

		/*
		** Make sure the wait() is interrupted by the signals
		** which cause us to exit.
		*/
		MR_signal_should_restart(SIGINT, MR_FALSE);
		MR_signal_should_restart(SIGTERM, MR_FALSE);
#ifdef SIGHUP
		MR_signal_should_restart(SIGHUP, MR_FALSE);
#endif
#ifdef SIGQUIT
		MR_signal_should_restart(SIGQUIT, MR_FALSE);
#endif

		while (1) {
		    wait_status = wait(&child_status);
		    if (wait_status == child_pid) {
			Status = child_status;
			break;
		    } else if (wait_status == -1) {
			if (errno == EINTR) {
			    if (MC_signalled) {
				/*
				** A normally fatal signal has been received,
				** so kill the child immediately.
				** Use SIGTERM, not MC_signal_received,
				** because the child may be inside a call
				** to system() which would cause SIGINT
				** to be ignored on some systems (e.g. Linux).
				*/
				kill(child_pid, SIGTERM);
			    }
			} else {
			    /*
			    ** This should never happen.
			    */
			    MR_perror(""error in wait(): "");
			    ForkStatus = 1;
			    Status = 1;
			    break;
			}
		    }
		}

		/*
		** Restore the system call signal behaviour. 
		*/
		MR_signal_should_restart(SIGINT, MR_TRUE);
		MR_signal_should_restart(SIGTERM, MR_TRUE);
#ifdef SIGHUP
		MR_signal_should_restart(SIGHUP, MR_TRUE);
#endif
#ifdef SIGQUIT
		MR_signal_should_restart(SIGQUIT, MR_TRUE);
#endif

	}
#else /* ! MC_CAN_FORK */
	IO = IO0;
	ForkStatus = 1;
	Status = 1;
#endif /* ! MC_CAN_FORK */
}").

	% call_io_pred(P, ExitStatus).
:- pred call_io_pred(io_pred::in(io_pred), int::out,
		io__state::di, io__state::uo) is det.
:- pragma export(call_io_pred(in(io_pred), out, di, uo), "MC_call_io_pred").

call_io_pred(P, Status) -->
	P(Success),
	{ Status = ( Success = yes -> 0 ; 1 ) }.

%-----------------------------------------------------------------------------%

build_with_module_options_and_output_redirect(ModuleName,
		ExtraOptions, Build, Succeeded, Info0, Info) -->	
    build_with_module_options(ModuleName, ExtraOptions,
	(pred(AllOptions::in, Succeeded1::out,
			Info1::in, Info2::out, di, uo) is det -->
	    build_with_output_redirect(ModuleName,
		(pred(ErrorStream::in, Succeeded2::out,
				Info3::in, Info4::out, di, uo) is det -->
		    Build(AllOptions, ErrorStream, Succeeded2, Info3, Info4)
		), Succeeded1, Info1, Info2)
	), Succeeded, Info0, Info).

build_with_output_redirect(ModuleName, Build, Succeeded, Info0, Info) -->
	redirect_output(ModuleName, RedirectResult, Info0, Info1),
	(
		{ RedirectResult = no },
		{ Succeeded = no },
		{ Info = Info1 }
	;
		{ RedirectResult = yes(ErrorStream) },
		Build(ErrorStream, Succeeded, Info1, Info2),
		unredirect_output(ModuleName, ErrorStream, Info2, Info)
	).

build_with_module_options(ModuleName, ExtraOptions,
		Build, Succeeded, Info0, Info) -->
	lookup_mmc_module_options(Info0 ^ options_variables,
		ModuleName, OptionsResult),
	(
		{ OptionsResult = no },
		{ Info = Info0 },
		{ Succeeded = no }
	;
		{ OptionsResult = yes(OptionArgs) }, 
		globals__io_get_globals(Globals),

		% --no-generate-mmake-module-dependencies disables
		% generation of `.d' files.
		{ AllOptionArgs = list__condense(
		    [["--no-generate-mmake-module-dependencies" | OptionArgs],
		    Info0 ^ option_args, ExtraOptions,
		    ["--no-make", "--no-rebuild"]]) },
	    	
		handle_options(AllOptionArgs, OptionsError, _, _, _),
		(
			{ OptionsError = yes(OptionsMessage) },
			{ Succeeded = no },
			{ Info = Info0 },
			usage_error(OptionsMessage)
		;
			{ OptionsError = no },
			Build(AllOptionArgs, Succeeded, Info0, Info),
			globals__io_set_globals(unsafe_promise_unique(Globals))
		)
	).

redirect_output(_ModuleName, MaybeErrorStream, Info, Info) -->
	%
	% Write the output to a temporary file first, so it's
	% easy to just print the part of the error file
	% that relates to the current command. It will
	% be appended to the error file later.
	%
	io__make_temp(ErrorFileName),
	io__open_output(ErrorFileName, ErrorFileRes),
	(
		{ ErrorFileRes = ok(ErrorOutputStream) },
		{ MaybeErrorStream = yes(ErrorOutputStream) }
	;
		{ ErrorFileRes = error(IOError) },
		{ MaybeErrorStream = no },
		io__write_string("** Error opening `"),
		io__write_string(ErrorFileName),
		io__write_string("' for output: "),
		{ io__error_message(IOError, Msg) },
		io__write_string(Msg),
		io__nl
	).

unredirect_output(ModuleName, ErrorOutputStream, Info0, Info) -->
   io__output_stream_name(ErrorOutputStream, TmpErrorFileName),
   io__close_output(ErrorOutputStream),

   io__open_input(TmpErrorFileName, TmpErrorInputRes),
   (
	{ TmpErrorInputRes = ok(TmpErrorInputStream) },
	module_name_to_file_name(ModuleName, ".err", yes, ErrorFileName),
	( { set__member(ModuleName, Info0 ^ error_file_modules) } -> 
		io__open_append(ErrorFileName, ErrorFileRes)
	;
		io__open_output(ErrorFileName, ErrorFileRes)
	),
	( 
	    { ErrorFileRes = ok(ErrorFileOutputStream) },
	    globals__io_lookup_int_option(output_compile_error_lines,
			LinesToWrite),
	    io__output_stream(CurrentOutputStream),
	    io__input_stream_foldl2_io(TmpErrorInputStream,
	    		write_error_char(ErrorFileOutputStream,
	    		CurrentOutputStream, LinesToWrite),
			0, TmpFileInputRes),
	    (
	    	{ TmpFileInputRes = ok(_) }
	    ;
		{ TmpFileInputRes = error(_, TmpFileInputError) },
		io__write_string("Error reading `"),
		io__write_string(TmpErrorFileName),
		io__write_string("': "),
		io__write_string(io__error_message(TmpFileInputError)),
		io__nl
	    ),

	    io__close_output(ErrorFileOutputStream),

	    { Info = Info0 ^ error_file_modules :=
			set__insert(Info0 ^ error_file_modules, ModuleName) }
	;
	    { ErrorFileRes = error(Error) },
	    { Info = Info0 },
	    io__write_string("Error opening `"),
	    io__write_string(TmpErrorFileName),
	    io__write_string("': "),
	    io__write_string(io__error_message(Error)),
	    io__nl
	),
	io__close_input(TmpErrorInputStream)
    ;
	{ TmpErrorInputRes = error(Error) },
	{ Info = Info0 },
	io__write_string("Error opening `"),
	io__write_string(TmpErrorFileName),
	io__write_string("': "),
	io__write_string(io__error_message(Error)),
	io__nl
    ),
    io__remove_file(TmpErrorFileName, _).

:- pred write_error_char(io__output_stream::in, io__output_stream::in,
		int::in, char::in, int::in, int::out,
		io__state::di, io__state::uo) is det.

write_error_char(FullOutputStream, PartialOutputStream, LineLimit,
		Char, Lines0, Lines) -->
	io__write_char(FullOutputStream, Char),
	( { Lines0 < LineLimit } ->
		io__write_char(PartialOutputStream, Char)
	;
		[]
	),
	{ Lines = ( Char = '\n' -> Lines0 + 1 ; Lines0 ) }.

%-----------------------------------------------------------------------------%

get_timestamp_file_timestamp(ModuleName - FileType,
		MaybeTimestamp, Info0, Info) -->
	globals__io_get_globals(Globals),
	{ TimestampExt = timestamp_extension(FileType) ->
		Ext = TimestampExt	
	;
		Ext = target_extension(Globals, FileType)
	},
	module_name_to_file_name(ModuleName, Ext, no, FileName),

	% We should only ever look for timestamp files
	% in the current directory. Timestamp files are
	% only used when processing a module, and only
	% modules in the current directory are processed.
	{ SearchDirs = [dir__this_directory] },
	get_file_timestamp(SearchDirs, FileName, MaybeTimestamp, Info0, Info).

get_dependency_timestamp(file(FileName, MaybeOption), MaybeTimestamp,
			Info0, Info) -->
	(       
		{ MaybeOption = yes(Option) },
		globals__io_lookup_accumulating_option(Option, SearchDirs)
	;       
		{ MaybeOption = no },
		{ SearchDirs = [dir__this_directory] }
	),
	get_file_timestamp(SearchDirs, FileName, MaybeTimestamp, Info0, Info).
get_dependency_timestamp(target(Target), MaybeTimestamp, Info0, Info) -->
	get_target_timestamp(Target, MaybeTimestamp, Info0, Info).

get_target_timestamp(ModuleName - FileType, MaybeTimestamp, Info0, Info) -->
	get_file_name(ModuleName - FileType, FileName, Info0, Info1),
	get_search_directories(FileType, SearchDirs),
	get_file_timestamp(SearchDirs, FileName, MaybeTimestamp0,
		Info1, Info2),
	(
		{ MaybeTimestamp0 = error(_) },
		{ FileType = intermodule_interface }
	->
		%
		% If a `.opt' file in another directory doesn't exist,
		% it just means that a library wasn't compiled with
		% `--intermodule-optimization'.
		%
		get_module_dependencies(ModuleName, MaybeImports,	
			Info2, Info3),
		{
			MaybeImports = yes(Imports),
			Imports ^ module_dir \= dir__this_directory
		->
			MaybeTimestamp = ok(oldest_timestamp),
			Info = Info3 ^ file_timestamps
					^ elem(FileName) := MaybeTimestamp
		;
			MaybeTimestamp = MaybeTimestamp0,
			Info = Info3
		}
	;
		{ MaybeTimestamp = MaybeTimestamp0 },
		{ Info = Info2 }
	).

get_file_name(ModuleName - FileType, FileName, Info0, Info) -->
	( { FileType = source } -> 
		%
		% In some cases the module name won't match the file
		% name (module mdb.parse might be in parse.m or mdb.m),
		% so we need to look up the file name here.
		% 
		get_module_dependencies(ModuleName, MaybeImports, Info0, Info),
		(
			{ MaybeImports = yes(Imports) },
			{ FileName = Imports ^ source_file_name }
		;
			{ MaybeImports = no },

			% Something has gone wrong generating the dependencies,
			% so just take a punt (which probably won't work).
			module_name_to_file_name(ModuleName, ".m",
				no, FileName)
		)
	;
		{ Info = Info0 },
		globals__io_get_globals(Globals),
		module_name_to_file_name(ModuleName,
			target_extension(Globals, FileType), no, FileName)
	).

get_file_timestamp(SearchDirs, FileName, MaybeTimestamp, Info0, Info) -->
	( { MaybeTimestamp0 = Info0 ^ file_timestamps ^ elem(FileName) } -> 
		{ Info = Info0 },
		{ MaybeTimestamp = MaybeTimestamp0 }
	;
		io__input_stream(OldInputStream),
		search_for_file(SearchDirs, FileName, SearchResult),
		( { SearchResult = yes(_) } ->
			io__input_stream_name(FullFileName),
			io__set_input_stream(OldInputStream, FileStream),
			io__close_input(FileStream),
			io__file_modification_time(FullFileName, TimeTResult),
			{
				TimeTResult = ok(TimeT),
				Timestamp = time_t_to_timestamp(TimeT),
				MaybeTimestamp = ok(Timestamp)
			;
				TimeTResult = error(Error),
				MaybeTimestamp = error(
						io__error_message(Error))
			},
			{ Info = Info0 ^ file_timestamps
					^ elem(FileName) := MaybeTimestamp }
		;
			{ MaybeTimestamp = error("file `" ++ FileName
							++ "' not found") },
			{ Info = Info0 }
		)
	).

:- pred get_search_directories(module_target_type::in, list(dir_name)::out,
		io__state::di, io__state::uo) is det.	

get_search_directories(FileType, SearchDirs) -->
	( { yes(SearchDirOpt) = search_for_file_type(FileType) } ->
		globals__io_lookup_accumulating_option(SearchDirOpt,
			SearchDirs)
	;
		{ SearchDirs = [dir__this_directory] }
	).

%-----------------------------------------------------------------------------%

remove_target_file(ModuleName - FileType, Info0, Info) -->
	remove_target_file(ModuleName, FileType, Info0, Info).

remove_target_file(ModuleName, FileType, Info0, Info) -->
	globals__io_get_globals(Globals),
	remove_file(ModuleName, target_extension(Globals, FileType),
		Info0, Info1),
	( { TimestampExt = timestamp_extension(FileType) } ->
		remove_file(ModuleName, TimestampExt, Info1, Info)
	;
		{ Info = Info1 }
	).

remove_file(ModuleName, Ext, Info0, Info) -->
	module_name_to_file_name(ModuleName, Ext, no, FileName),
	remove_file(FileName, Info0, Info).

remove_file(FileName, Info0, Info) -->
	io__remove_file(FileName, _),
	{ Info = Info0 ^ file_timestamps :=
			map__delete(Info0 ^ file_timestamps, FileName) }.

%-----------------------------------------------------------------------------%

make_target_list(Ks, V) = list__map((func(K) = K - V), Ks).

make_dependency_list(ModuleNames, FileType) =
	list__map((func(Module) = target(Module - FileType)), ModuleNames).

target_extension(_, source) = ".m".
target_extension(_, errors) = ".err".
target_extension(_, private_interface) = ".int0".
target_extension(_, long_interface) = ".int".
target_extension(_, short_interface) = ".int2".
target_extension(_, unqualified_short_interface) = ".int3".
target_extension(_, intermodule_interface) = ".opt".
target_extension(_, aditi_code) = ".rlo".
target_extension(_, c_header) = ".h".
target_extension(_, c_code) = ".c".
target_extension(_, il_code) = ".il".
target_extension(_, il_asm) = ".dll". % XXX ".exe" if the module contains main.
target_extension(_, java_code) = ".java".
target_extension(_, asm_code(non_pic)) = ".s".
target_extension(_, asm_code(pic)) = ".pic_s".
target_extension(Globals, object_code(non_pic)) = Ext :-
	globals__lookup_string_option(Globals, object_file_extension, Ext).
target_extension(Globals, object_code(pic)) = Ext :-
	globals__lookup_string_option(Globals, pic_object_file_extension, Ext).

linked_target_extension(Globals, executable) = Ext :-
	globals__lookup_string_option(Globals, executable_file_extension, Ext).
linked_target_extension(Globals, static_library) = Ext :-
	globals__lookup_string_option(Globals, library_extension, Ext).
linked_target_extension(Globals, shared_library) = Ext :-
	globals__lookup_string_option(Globals, shared_library_extension, Ext).

	% Note that we need a timestamp file for `.err' files because
	% errors are written to the `.err' file even when writing interfaces.
	% The timestamp is only updated when compiling to target code.
timestamp_extension(errors) = ".err_date".
timestamp_extension(private_interface) = ".date0".
timestamp_extension(long_interface) = ".date".
timestamp_extension(short_interface) = ".date".
timestamp_extension(unqualified_short_interface) = ".date3".
timestamp_extension(intermodule_interface) = ".optdate".
timestamp_extension(c_code) = ".c_date".
timestamp_extension(il_code) = ".il_date".
timestamp_extension(java_code) = ".java_date".
timestamp_extension(asm_code(non_pic)) = ".s_date".
timestamp_extension(asm_code(pic)) = ".pic_s_date".

:- func search_for_file_type(module_target_type) = maybe(option).

search_for_file_type(source) = no.
search_for_file_type(errors) = no.
	% XXX only for inter-module optimization.
search_for_file_type(private_interface) = yes(search_directories).
search_for_file_type(long_interface) = yes(search_directories).
search_for_file_type(short_interface) = yes(search_directories).
search_for_file_type(unqualified_short_interface) = yes(search_directories).
search_for_file_type(intermodule_interface) = yes(intermod_directories).
search_for_file_type(aditi_code) = no.
search_for_file_type(c_header) = yes(c_include_directory).
search_for_file_type(c_code) = no.
search_for_file_type(il_code) = no.
search_for_file_type(il_asm) = no.
search_for_file_type(java_code) = no.
search_for_file_type(asm_code(_)) = no.
search_for_file_type(object_code(_)) = no.

%-----------------------------------------------------------------------------%

debug_msg(P) -->
	globals__io_lookup_bool_option(debug_make, Debug),
	( { Debug = yes } ->
		P,
		io__flush_output
	;
		[]
	).

verbose_msg(P) -->
	globals__io_lookup_bool_option(verbose_make, Verbose),
	( { Verbose = yes } ->
		P,
		io__flush_output
	;
		[]
	).

debug_file_msg(TargetFile, Msg) -->
	debug_msg(
		(pred(di, uo) is det -->
			write_target_file(TargetFile),
			io__write_string(": "),
			io__write_string(Msg),
			io__nl
		)).

write_dependency_file(target(TargetFile)) --> write_target_file(TargetFile).
write_dependency_file(file(FileName, _)) --> io__write_string(FileName).

write_target_file(ModuleName - FileType) -->
	prog_out__write_sym_name(ModuleName),
	globals__io_get_globals(Globals),
	io__write_string(target_extension(Globals, FileType)).

maybe_make_linked_target_message(TargetFile) -->
	verbose_msg(
		(pred(di, uo) is det -->
			io__write_string("Making "),
			io__write_string(TargetFile),
			io__nl
		)).

maybe_make_target_message(TargetFile) -->
	io__output_stream(OutputStream),
	maybe_make_target_message(OutputStream, TargetFile).

maybe_make_target_message(OutputStream, TargetFile) -->
	verbose_msg(
		(pred(di, uo) is det -->
			io__set_output_stream(OutputStream, OldOutputStream),
			io__write_string("Making "),
			write_target_file(TargetFile),
			io__nl,
			io__set_output_stream(OldOutputStream, _)
		)).

target_file_error(TargetFile) -->
	io__write_string("** Error making `"),
	write_target_file(TargetFile),
	io__write_string("'.\n").

file_error(TargetFile) -->
	io__write_string("** Error making `"),
	io__write_string(TargetFile),
	io__write_string("'.\n").

%-----------------------------------------------------------------------------%
