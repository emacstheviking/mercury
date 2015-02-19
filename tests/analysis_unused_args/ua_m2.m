%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%

:- module ua_m2.
:- interface.

:- pred bbb(int::in, int::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module ua_m3.

:- pragma no_inline(bbb/2).

bbb(N, M) :-
    ccc(N, M).