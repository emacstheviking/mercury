%-----------------------------------------------------------------------------%
% Copyright (C) 1993-1995, 1997-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: array.m
% Main authors: fjh, bromage
% Stability: medium-low

% This module provides dynamically-sized one-dimensional arrays.
% Array indices start at zero.

% By default, the array__set and array__lookup procedures will check
% for bounds errors.  But for better performance, it is possible to
% disable some of the checking by compiling with `--intermodule-optimization'
% and with the C macro symbol `ML_OMIT_ARRAY_BOUNDS_CHECKS'
% defined, e.g. by using `MCFLAGS=--intermodule-optimization' and
% `CFLAGS=-DML_OMIT_ARRAY_BOUNDS_CHECKS' in your Mmakefile,
% or by compiling with the command
% `mmc --intermodule-optimization --cflags -DML_OMIT_ARRAY_BOUNDS_CHECKS'.
%
% For maximum performance, all bounds checking can be disabled by
% recompiling this module using `CFLAGS=-DML_OMIT_ARRAY_BOUNDS_CHECKS'
% or `mmc --cflags -DML_OMIT_ARRAY_BOUNDS_CHECKS' as above. You can
% either recompile the entire library, or just copy `array.m' to your
% application's source directory and link with it directly instead of as
% part of the library.
%

% WARNING!
%
% Arrays are currently not unique objects - until this situation is
% resolved it is up to the programmer to ensure that arrays are used
% in such a way as to preserve correctness.  In the absence of mode
% reordering, one should therefore assume that evaluation will take
% place in left-to-right order.  For example, the following code will
% probably not work as expected (f is a function, A an array, I an
% index, and X an appropriate value):
%
%       Y = f(A ^ elem(I) := X, A ^ elem(I))
%
% The compiler is likely to compile this as
%
%       V0 = A ^ elem(I) := X,
%       V1 = A ^ elem(I),
%       Y  = f(V0, V1)
%
% and will be unaware that the first line should be ordered
% *after* the second.  The safest thing to do is write things out
% by hand in the form
%
%       A0I = A0 ^ elem(I),
%       A1  = A0 ^ elem(I) := X,
%       Y   = f(A1, A0I)

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module array.
:- interface.
:- import_module list, std_util, random.

:- type array(T).

:- inst array(I) == bound(array(I)).
:- inst array == array(ground).
:- inst array_skel == array(free).

	% XXX the current Mercury compiler doesn't support `ui' modes,
	% so to work-around that problem, we currently don't use
	% unique modes in this module.

% :- inst uniq_array(I) == unique(array(I)).
% :- inst uniq_array == uniq_array(unique).
:- inst uniq_array(I) == bound(array(I)). % XXX work-around
:- inst uniq_array == uniq_array(ground). % XXX work-around
:- inst uniq_array_skel == uniq_array(free).

:- mode array_di == di(uniq_array).
:- mode array_uo == out(uniq_array).
:- mode array_ui == in(uniq_array).

% :- inst mostly_uniq_array(I) == mostly_unique(array(I)).
% :- inst mostly_uniq_array == mostly_uniq_array(mostly_unique).
:- inst mostly_uniq_array(I) == bound(array(I)).	% XXX work-around
:- inst mostly_uniq_array == mostly_uniq_array(ground).	% XXX work-around
:- inst mostly_uniq_array_skel == mostly_uniq_array(free).

:- mode array_mdi == mdi(mostly_uniq_array).
:- mode array_muo == out(mostly_uniq_array).
:- mode array_mui == in(mostly_uniq_array).

	% An `array__index_out_of_bounds' is the exception thrown
	% on out-of-bounds array accesses. The string describes
	% the predicate or function reporting the error.
:- type array__index_out_of_bounds
	---> array__index_out_of_bounds(string).

%-----------------------------------------------------------------------------%

	% array__make_empty_array(Array) creates an array of size zero
	% starting at lower bound 0.
	%
:- pred array__make_empty_array(array(T)::array_uo) is det.

:- func array__make_empty_array = (array(T)::array_uo) is det.

	% array__init(Size, Init, Array) creates an array
	% with bounds from 0 to Size-1, with each element initialized to Init.
	%
:- pred array__init(int, T, array(T)).
:- mode array__init(in, in, array_uo) is det.

:- func array__init(int, T) = array(T).
:- mode array__init(in, in) = array_uo is det.

	% array/1 is a function that constructs an array from a list.
	% (It does the same thing as the predicate array__from_list/2.)
	% The syntax `array([...])' is used to represent arrays
	% for io__read, io__write, term_to_type, and type_to_term.
	%
:- func array(list(T)) = array(T).
:- mode array(in) = array_uo is det.

%-----------------------------------------------------------------------------%

	% array__min returns the lower bound of the array.
	% Note: in this implementation, the lower bound is always zero.
	%
:- pred array__min(array(_T), int).
:- mode array__min(array_ui, out) is det.
:- mode array__min(in, out) is det.

:- func array__min(array(_T)) = int.
:- mode array__min(array_ui) = out is det.
:- mode array__min(in) = out is det.

:- func array__least_index(array(T)) = int.
:- mode array__least_index(array_ui) = out is det.
:- mode array__least_index(in) = out is det.

	% array__max returns the upper bound of the array.
	%
:- pred array__max(array(_T), int).
:- mode array__max(array_ui, out) is det.
:- mode array__max(in, out) is det.

:- func array__max(array(_T)) = int.
:- mode array__max(array_ui) = out is det.
:- mode array__max(in) = out is det.

:- func array__greatest_index(array(T)) = int.
:- mode array__greatest_index(array_ui) = out is det.
:- mode array__greatest_index(in) = out is det.

	% array__size returns the length of the array,
	% i.e. upper bound - lower bound + 1.
	%
:- pred array__size(array(_T), int).
:- mode array__size(array_ui, out) is det.
:- mode array__size(in, out) is det.

:- func array__size(array(_T)) = int.
:- mode array__size(array_ui) = out is det.
:- mode array__size(in) = out is det.

	% array__bounds returns the upper and lower bounds of an array.
	% Note: in this implementation, the lower bound is always zero.
	%
:- pred array__bounds(array(_T), int, int).
:- mode array__bounds(array_ui, out, out) is det.
:- mode array__bounds(in, out, out) is det.

	% array__in_bounds checks whether an index is in the bounds
	% of an array.
	%
:- pred array__in_bounds(array(_T), int).
:- mode array__in_bounds(array_ui, in) is semidet.
:- mode array__in_bounds(in, in) is semidet.

%-----------------------------------------------------------------------------%

	% array__lookup returns the Nth element of an array.
	% Throws an exception if the index is out of bounds.
	%
:- pred array__lookup(array(T), int, T).
:- mode array__lookup(array_ui, in, out) is det.
:- mode array__lookup(in, in, out) is det.

:- func array__lookup(array(T), int) = T.
:- mode array__lookup(array_ui, in) = out is det.
:- mode array__lookup(in, in) = out is det.

	% array__semidet_lookup returns the Nth element of an array.
	% It fails if the index is out of bounds.
	%
:- pred array__semidet_lookup(array(T), int, T).
:- mode array__semidet_lookup(array_ui, in, out) is semidet.
:- mode array__semidet_lookup(in, in, out) is semidet.

	% array__set sets the nth element of an array, and returns the
	% resulting array (good opportunity for destructive update ;-).
	% Throws an exception if the index is out of bounds.
	%
:- pred array__set(array(T), int, T, array(T)).
:- mode array__set(array_di, in, in, array_uo) is det.

:- func array__set(array(T), int, T) = array(T).
:- mode array__set(array_di, in, in) = array_uo is det.

	% array__semidet_set sets the nth element of an array,
	% and returns the resulting array.
	% It fails if the index is out of bounds.
	%
:- pred array__semidet_set(array(T), int, T, array(T)).
:- mode array__semidet_set(array_di, in, in, array_uo) is semidet.

	% array__slow_set sets the nth element of an array,
	% and returns the resulting array.  The initial array is not
	% required to be unique, so the implementation may not be able to use
	% destructive update.
	% It is an error if the index is out of bounds.
	%
:- pred array__slow_set(array(T), int, T, array(T)).
:- mode array__slow_set(array_ui, in, in, array_uo) is det.
:- mode array__slow_set(in, in, in, array_uo) is det.

:- func array__slow_set(array(T), int, T) = array(T).
:- mode array__slow_set(array_ui, in, in) = array_uo is det.
:- mode array__slow_set(in, in, in) = array_uo is det.

	% array__semidet_slow_set sets the nth element of an array,
	% and returns the resulting array.  The initial array is not
	% required to be unique, so the implementation may not be able to use
	% destructive update.
	% It fails if the index is out of bounds.
	%
:- pred array__semidet_slow_set(array(T), int, T, array(T)).
:- mode array__semidet_slow_set(array_ui, in, in, array_uo) is semidet.
:- mode array__semidet_slow_set(in, in, in, array_uo) is semidet.

	% Field selection for arrays.
	% Array ^ elem(Index) = array__lookup(Array, Index).
	%
:- func array__elem(int, array(T)) = T.
:- mode array__elem(in, array_ui) = out is det.
:- mode array__elem(in, in) = out is det.

	% Field update for arrays.
	% (Array ^ elem(Index) := Value) = array__set(Array, Index, Value).
	%
:- func 'array__elem :='(int, array(T), T) = array(T).
:- mode 'array__elem :='(in, array_di, in) = array_uo is det.

%-----------------------------------------------------------------------------%

	% array__copy(Array0, Array):
	% Makes a new unique copy of an array.
	%
:- pred array__copy(array(T), array(T)).
:- mode array__copy(array_ui, array_uo) is det.
:- mode array__copy(in, array_uo) is det.

:- func array__copy(array(T)) = array(T).
:- mode array__copy(array_ui) = array_uo is det.
:- mode array__copy(in) = array_uo is det.

	% array__resize(Array0, Size, Init, Array):
	% The array is expanded or shrunk to make it fit
	% the new size `Size'.  Any new entries are filled
	% with `Init'.
	%
:- pred array__resize(array(T), int, T, array(T)).
:- mode array__resize(array_di, in, in, array_uo) is det.

:- func array__resize(array(T), int, T) = array(T).
:- mode array__resize(array_di, in, in) = array_uo is det.

	% array__shrink(Array0, Size, Array):
	% The array is shrunk to make it fit the new size `Size'.
	% Throws an exception if `Size' is larger than the size of `Array0'.
	%
:- pred array__shrink(array(T), int, array(T)).
:- mode array__shrink(array_di, in, array_uo) is det.

:- func array__shrink(array(T), int) = array(T).
:- mode array__shrink(array_di, in) = array_uo is det.

	% array__from_list takes a list,
	% and returns an array containing those elements in
	% the same order that they occurred in the list.
	%
:- pred array__from_list(list(T), array(T)).
:- mode array__from_list(in, array_uo) is det.

:- func array__from_list(list(T)) = array(T).
:- mode array__from_list(in) = array_uo is det.

	% array__to_list takes an array and returns a list containing
	% the elements of the array in the same order that they
	% occurred in the array.
	%
:- pred array__to_list(array(T), list(T)).
:- mode array__to_list(array_ui, out) is det.
:- mode array__to_list(in, out) is det.

:- func array__to_list(array(T)) = list(T).
:- mode array__to_list(array_ui) = out is det.
:- mode array__to_list(in) = out is det.

	% array__fetch_items takes an array and a lower and upper
	% index, and places those items in the array between these
	% indices into a list.  It is an error if either index is
	% out of bounds.
	%
:- pred array__fetch_items(array(T), int, int, list(T)).
:- mode array__fetch_items(in, in, in, out) is det.

:- func array__fetch_items(array(T), int, int) = list(T).
:- mode array__fetch_items(array_ui, in, in) = out is det.
:- mode array__fetch_items(in, in, in) = out is det.

	% array__bsearch takes an array, an element to be matched
	% and a comparison predicate and returns the position of
	% the first occurrence in the array of an element which is
	% equivalent to the given one in the ordering provided.
	% Assumes the array is sorted according to this ordering.
	% Fails if the element is not present.
	%
:- pred array__bsearch(array(T), T, comparison_pred(T), maybe(int)).
:- mode array__bsearch(array_ui, in, in(comparison_pred), out) is det.
:- mode array__bsearch(in, in, in(comparison_pred), out) is det.

:- func array__bsearch(array(T), T, comparison_func(T)) = maybe(int).
:- mode array__bsearch(array_ui, in, in(comparison_func)) = out is det.
:- mode array__bsearch(in, in, in(comparison_func)) = out is det.

	% array__map(Closure, OldArray, NewArray) applys `Closure' to
	% each of the elements of `OldArray' to create `NewArray'.
	%
:- pred array__map(pred(T1, T2), array(T1), array(T2)).
:- mode array__map(pred(in, out) is det, array_di, array_uo) is det.

:- func array__map(func(T1) = T2, array(T1)) = array(T2).
:- mode array__map(func(in) = out is det, array_di) = array_uo is det.

:- func array_compare(array(T), array(T)) = comparison_result.
:- mode array_compare(in, in) = uo is det.

	% array__sort(Array) returns a version of Array sorted
	% into ascending order.
	%
	% This sort is not stable.  That is, elements that
	% compare/3 decides are equal will appear together in
	% the sorted array, but not necessarily in the same
	% order in which they occurred in the input array.
	% This is primarily only an issue with types with
	% user-defined equivalence for which `equivalent'
	% objects are otherwise distinguishable.
	%
:- func array__sort(array(T)) = array(T).
:- mode array__sort(array_di) = array_uo is det.

	% array__foldl(Fn, Array, X) is equivalent to
	% 	list__foldl(Fn, array__to_list(Array), X)
	% but more efficient.
	%
:- func array__foldl(func(T1, T2) = T2, array(T1), T2) = T2.
:- mode array__foldl(func(in, in) = out is det, array_ui, in) = out is det.
:- mode array__foldl(func(in, in) = out is det, in, in) = out is det.
:- mode array__foldl(func(in, di) = uo is det, array_ui, di) = uo is det.
:- mode array__foldl(func(in, di) = uo is det, in, di) = uo is det.

	% array__foldr(Fn, Array, X) is equivalent to
	% 	list__foldr(Fn, array__to_list(Array), X)
	% but more efficient.
	%
:- func array__foldr(func(T1, T2) = T2, array(T1), T2) = T2.
:- mode array__foldr(func(in, in) = out is det, array_ui, in) = out is det.
:- mode array__foldr(func(in, in) = out is det, in, in) = out is det.
:- mode array__foldr(func(in, di) = uo is det, array_ui, di) = uo is det.
:- mode array__foldr(func(in, di) = uo is det, in, di) = uo is det.

	% array__random_permutation(A0, A, RS0, RS) permutes the elements in
	% A0 given random seed RS0 and returns the permuted array in A
	% and the next random seed in RS.
	%
:- pred array__random_permutation(array(T), array(T),
	random__supply, random__supply).
:- mode array__random_permutation(array_di, array_uo, mdi, muo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

% Everything beyond here is not intended as part of the public interface,
% and will not appear in the Mercury Library Reference Manual.

:- import_module exception, int, require, string.

%
% Define the array type appropriately for the different targets.
% Note that the definitions here should match what is output by
% mlds_to_c.m, mlds_to_il.m, or mlds_to_java.m for mlds__mercury_array_type.
%

	% MR_ArrayPtr is defined in runtime/mercury_library_types.h.
:- pragma foreign_type("C", array(T), "MR_ArrayPtr")
	where equality is array__array_equal,
	comparison is array__array_compare.

:- pragma foreign_type(il,  array(T), "class [mscorlib]System.Array")
	where equality is array__array_equal,
	comparison is array__array_compare.

	% We can't use `java.lang.Object []', since we want
	% a generic type that is capable of holding any kind
	% of array, including e.g. `int []'.
	% Java doesn't have any equivalent of .NET's System.Array
	% class, so we just use the universal base `java.lang.Object'.
:- pragma foreign_type(java,  array(T), "/* Array */ java.lang.Object")
	where equality is array__array_equal,
	comparison is array__array_compare.

	% unify/2 for arrays

:- pred array_equal(array(T)::in, array(T)::in) is semidet.
:- pragma export(array_equal(in, in), "ML_array_equal").
:- pragma terminates(array_equal/2).

array_equal(Array1, Array2) :-
	( if
		array__size(Array1, Size),
		array__size(Array2, Size)
	then
		array__equal_elements(0, Size, Array1, Array2)
	else
		fail
	).

:- pred array__equal_elements(int, int, array(T), array(T)).
:- mode array__equal_elements(in, in, in, in) is semidet.

array__equal_elements(N, Size, Array1, Array2) :-
	( N = Size ->
		true
	;
		array__lookup(Array1, N, Elem),
		array__lookup(Array2, N, Elem),
		N1 = N + 1,
		array__equal_elements(N1, Size, Array1, Array2)
	).

	% compare/3 for arrays

:- pred array_compare(comparison_result::uo, array(T)::in, array(T)::in)
	is det.
:- pragma export(array_compare(uo, in, in), "ML_array_compare").
:- pragma terminates(array_compare/3).

array_compare(Result, Array1, Array2) :-
	array__size(Array1, Size1),
	array__size(Array2, Size2),
	compare(SizeResult, Size1, Size2),
	( SizeResult = (=) ->
		array__compare_elements(0, Size1, Array1, Array2, Result)
	;
		Result = SizeResult
	).

:- pred array__compare_elements(int, int, array(T), array(T),
	comparison_result).
:- mode array__compare_elements(in, in, in, in, uo) is det.

array__compare_elements(N, Size, Array1, Array2, Result) :-
	( N = Size ->
		Result = (=)
	;
		array__lookup(Array1, N, Elem1),
		array__lookup(Array2, N, Elem2),
		compare(ElemResult, Elem1, Elem2),
		( ElemResult = (=) ->
			N1 = N + 1,
			array__compare_elements(N1, Size, Array1, Array2,
				Result)
		;
			Result = ElemResult
		)
	).

%-----------------------------------------------------------------------------%

:- pred bounds_checks is semidet.
:- pragma inline(bounds_checks/0).

:- pragma foreign_proc("C",
	bounds_checks,
	[will_not_call_mercury, promise_pure, thread_safe],
"
#ifdef ML_OMIT_ARRAY_BOUNDS_CHECKS
	SUCCESS_INDICATOR = MR_FALSE;
#else
	SUCCESS_INDICATOR = MR_TRUE;
#endif
").

:- pragma foreign_proc("C#",
	bounds_checks,
	[will_not_call_mercury, promise_pure, thread_safe],
"
#if ML_OMIT_ARRAY_BOUNDS_CHECKS
	SUCCESS_INDICATOR = false;
#else
	SUCCESS_INDICATOR = true;
#endif
").

:- pragma foreign_proc("Java",
	bounds_checks,
	[will_not_call_mercury, promise_pure, thread_safe],
"
	// never do bounds checking for Java (throw exceptions instead)
	succeeded = false;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_decl("C", "
#include ""mercury_heap.h""		/* for MR_maybe_record_allocation() */
#include ""mercury_library_types.h""	/* for MR_ArrayPtr */

/*
** We do not yet record term sizes for arrays in term size profiling
** grades. Doing so would require
**
** - modifying ML_alloc_array to allocate an extra word for the size;
** - modifying all the predicates that call ML_alloc_array to compute the
**   size of the array (the sum of the sizes of the elements and the size of
**   the array itself);
** - modifying all the predicates that update array elements to compute the
**   difference between the sizes of the terms being added to and deleted from
**   the array, and updating the array size accordingly.
*/

#define	ML_alloc_array(newarray, arraysize, proclabel)			\
	do {								\
		MR_Word	newarray_word;					\
		MR_offset_incr_hp_msg(newarray_word, 0, (arraysize),	\
			proclabel, ""array:array/1"");			\
		(newarray) = (MR_ArrayPtr) newarray_word;		\
	} while (0)
").

:- pragma foreign_decl("C", "
void ML_init_array(MR_ArrayPtr, MR_Integer size, MR_Word item);
").

:- pragma foreign_code("C", "
/*
** The caller is responsible for allocating the memory for the array.
** This routine does the job of initializing the already-allocated memory.
*/
void
ML_init_array(MR_ArrayPtr array, MR_Integer size, MR_Word item)
{
	MR_Integer i;

	array->size = size;
	for (i = 0; i < size; i++) {
		array->elements[i] = item;
	}
}
").

array__init(Size, Item, Array) :-
	( Size < 0 ->
		error("array__init: negative size")
	;
		array__init_2(Size, Item, Array)
	).

:- pred array__init_2(int, T, array(T)).
:- mode array__init_2(in, in, array_uo) is det.

:- pragma foreign_proc("C",
	array__init_2(Size::in, Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	ML_alloc_array(Array, Size + 1, MR_PROC_LABEL);
	ML_init_array(Array, Size, Item);
").

:- pragma foreign_proc("C",
	array__make_empty_array(Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	ML_alloc_array(Array, 1, MR_PROC_LABEL);
	ML_init_array(Array, 0, 0);
").

:- pragma foreign_proc("C#",
	array__init_2(Size::in, Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Array = System.Array.CreateInstance(Item.GetType(), Size);
	for (int i = 0; i < Size; i++) {
		Array.SetValue(Item, i);
	}
").
:- pragma foreign_proc("C#",
	array__make_empty_array(Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	// XXX A better solution then using the null pointer to represent
	// the empty array would be to create an array of size 0.  However
	// we need to determine the element type of the array before we can
	// do that.  This could be done by examing the RTTI of the array
	// type and then using System.Type.GetType(""<mercury type>"") to
	// determine it.  However constructing the <mercury type> string is
	// a non-trival amount of work.
	Array = null;
").

:- pragma foreign_proc("Java",
	array__init_2(Size::in, Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	java.lang.Class itemClass = Item.getClass();

	Array = java.lang.reflect.Array.newInstance(itemClass, Size);
	for (int i = 0; i < Size; i++) {
		java.lang.reflect.Array.set(Array, i, Item);
	}
").
:- pragma foreign_proc("Java",
	array__make_empty_array(Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	// XXX as per C#
	Array = null;
").

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	array__min(Array::array_ui, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").
:- pragma foreign_proc("C",
	array__min(Array::in, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").

:- pragma foreign_proc("C#",
	array__min(Array::array_ui, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").
:- pragma foreign_proc("C#",
	array__min(Array::in, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").

:- pragma foreign_proc("Java",
	array__min(_Array::array_ui, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").
:- pragma foreign_proc("Java",
	array__min(_Array::in, Min::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	/* Array not used */
	Min = 0;
").

:- pragma foreign_proc("C",
	array__max(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Max = Array->size - 1;
").
:- pragma foreign_proc("C",
	array__max(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Max = Array->size - 1;
").
:- pragma foreign_proc("C#",
	array__max(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = Array.Length - 1;
	} else {
		Max = -1;
	}
").
:- pragma foreign_proc("C#",
	array__max(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = Array.Length - 1;
	} else {
		Max = -1;
	}
").

:- pragma foreign_proc("Java",
	array__max(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = java.lang.reflect.Array.getLength(Array) - 1;
	} else {
		Max = -1;
	}
").
:- pragma foreign_proc("Java",
	array__max(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = java.lang.reflect.Array.getLength(Array) - 1;
	} else {
		Max = -1;
	}
").

array__bounds(Array, Min, Max) :-
	array__min(Array, Min),
	array__max(Array, Max).

%-----------------------------------------------------------------------------%

:- pragma foreign_proc("C",
	array__size(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Max = Array->size;
").
:- pragma foreign_proc("C",
	array__size(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Max = Array->size;
").

:- pragma foreign_proc("C#",
	array__size(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = Array.Length;
	} else {
		Max = 0;
	}
").
:- pragma foreign_proc("C#",
	array__size(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = Array.Length;
	} else {
		Max = 0;
	}
").

:- pragma foreign_proc("Java",
	array__size(Array::array_ui, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = java.lang.reflect.Array.getLength(Array);
	} else {
		Max = 0;
	}
").
:- pragma foreign_proc("Java",
	array__size(Array::in, Max::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array != null) {
		Max = java.lang.reflect.Array.getLength(Array);
	} else {
		Max = 0;
	}
").

%-----------------------------------------------------------------------------%

array__in_bounds(Array, Index) :-
	array__bounds(Array, Min, Max),
	Min =< Index, Index =< Max.

array__semidet_lookup(Array, Index, Item) :-
	( if array__in_bounds(Array, Index) then
		array__unsafe_lookup(Array, Index, Item)
	else
		fail
	).

array__semidet_set(Array0, Index, Item, Array) :-
	( if array__in_bounds(Array0, Index) then
		array__unsafe_set(Array0, Index, Item, Array)
	else
		fail
	).

array__semidet_slow_set(Array0, Index, Item, Array) :-
	( if array__in_bounds(Array0, Index) then
		array__slow_set(Array0, Index, Item, Array)
	else
		fail
	).

array__slow_set(Array0, Index, Item, Array) :-
	array__copy(Array0, Array1),
	array__set(Array1, Index, Item, Array).

%-----------------------------------------------------------------------------%

array__lookup(Array, Index, Item) :-
	( bounds_checks, \+ array__in_bounds(Array, Index) ->
		out_of_bounds_error(Array, Index, "array__lookup")
	;
		array__unsafe_lookup(Array, Index, Item)
	).

:- pred array__unsafe_lookup(array(T), int, T).
:- mode array__unsafe_lookup(array_ui, in, out) is det.
:- mode array__unsafe_lookup(in, in, out) is det.

:- pragma foreign_proc("C",
	array__unsafe_lookup(Array::array_ui, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Item = Array->elements[Index];
}").
:- pragma foreign_proc("C",
	array__unsafe_lookup(Array::in, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Item = Array->elements[Index];
}").

:- pragma foreign_proc("C#",
	array__unsafe_lookup(Array::array_ui, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Item = Array.GetValue(Index);
}").
:- pragma foreign_proc("C#",
	array__unsafe_lookup(Array::in, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Item = Array.GetValue(Index);
}").

:- pragma foreign_proc("Java",
	array__unsafe_lookup(Array::array_ui, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Item = java.lang.reflect.Array.get(Array, Index);
").
:- pragma foreign_proc("Java",
	array__unsafe_lookup(Array::in, Index::in, Item::out),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Item = java.lang.reflect.Array.get(Array, Index);
").

%-----------------------------------------------------------------------------%

array__set(Array0, Index, Item, Array) :-
	( bounds_checks, \+ array__in_bounds(Array0, Index) ->
		out_of_bounds_error(Array0, Index, "array__set")
	;
		array__unsafe_set(Array0, Index, Item, Array)
	).

:- pred array__unsafe_set(array(T), int, T, array(T)).
:- mode array__unsafe_set(array_di, in, in, array_uo) is det.

:- pragma foreign_proc("C",
	array__unsafe_set(Array0::array_di, Index::in,
		Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Array0->elements[Index] = Item;	/* destructive update! */
	Array = Array0;
}").

:- pragma foreign_proc("C#",
	array__unsafe_set(Array0::array_di, Index::in,
		Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"{
	Array0.SetValue(Item, Index);	/* destructive update! */
	Array = Array0;
}").

:- pragma foreign_proc("Java",
	array__unsafe_set(Array0::array_di, Index::in,
		Item::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	java.lang.reflect.Array.set(Array0, Index, Item);
	Array = Array0;			/* destructive update! */
").

%-----------------------------------------------------------------------------%

/****
lower bounds other than zero are not supported
	% array__resize takes an array and new lower and upper bounds.
	% the array is expanded or shrunk at each end to make it fit
	% the new bounds.
:- pred array__resize(array(T), int, int, array(T)).
:- mode array__resize(in, in, in, out) is det.
****/

:- pragma foreign_decl("C", "
void ML_resize_array(MR_ArrayPtr new_array, MR_ArrayPtr old_array,
	MR_Integer array_size, MR_Word item);
").

:- pragma foreign_code("C", "
/*
** The caller is responsible for allocating the storage for the new array.
** This routine does the job of copying the old array elements to the
** new array, initializing any additional elements in the new array,
** and deallocating the old array.
*/
void
ML_resize_array(MR_ArrayPtr array, MR_ArrayPtr old_array,
	MR_Integer array_size, MR_Word item)
{
	MR_Integer i;
	MR_Integer elements_to_copy;

	elements_to_copy = old_array->size;
	if (elements_to_copy > array_size) {
		elements_to_copy = array_size;
	}

	array->size = array_size;
	for (i = 0; i < elements_to_copy; i++) {
		array->elements[i] = old_array->elements[i];
	}
	for (; i < array_size; i++) {
		array->elements[i] = item;
	}

	/*
	** since the mode on the old array is `array_di', it is safe to
	** deallocate the storage for it
	*/
#ifdef MR_CONSERVATIVE_GC
	GC_FREE(old_array);
#endif
}
").

:- pragma foreign_proc("C",
	array__resize(Array0::array_di, Size::in, Item::in,
		Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if ((Array0)->size == Size) {
		Array = Array0;
	} else {
		ML_alloc_array(Array, Size + 1, MR_PROC_LABEL);
		ML_resize_array(Array, Array0, Size, Item);
	}
").

:- pragma foreign_proc("C#",
	array__resize(Array0::array_di, Size::in, Item::in,
		Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array0 == null) {
		Array = System.Array.CreateInstance(Item.GetType(), Size);
		for (int i = 0; i < Size; i++) {
			Array.SetValue(Item, i);
		}
	}
	else if (Array0.Length == Size) {
		Array = Array0;
	} else if (Array0.Length > Size) {
		Array = System.Array.CreateInstance(Item.GetType(), Size);
		System.Array.Copy(Array0, Array, Size);
	} else {
		Array = System.Array.CreateInstance(Item.GetType(), Size);
		System.Array.Copy(Array0, Array, Array0.Length);
		for (int i = Array0.Length; i < Size; i++) {
			Array.SetValue(Item, i);
		}
	}
").

:- pragma foreign_proc("Java",
	array__resize(Array0::array_di, Size::in, Item::in,
		Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	java.lang.Class itemClass = Item.getClass();

	if (Size == 0) {
		Array = null;
	} else if (Array0 == null) {
		Array = java.lang.reflect.Array.newInstance(itemClass, Size);
		for (int i = 0; i < Size; i++) {
			java.lang.reflect.Array.set(Array, i, Item);
		}
	} else if (java.lang.reflect.Array.getLength(Array0) == Size) {
		Array = Array0;
	} else {
		Array = java.lang.reflect.Array.newInstance(itemClass, Size);

		int i;
		for (i = 0; i < java.lang.reflect.Array.getLength(Array0) &&
				i < Size; i++)
		{
			java.lang.reflect.Array.set(Array, i,
					java.lang.reflect.Array.get(Array0, i)
					);
		}
		for (/*i = Array0.length*/; i < Size; i++) {
			java.lang.reflect.Array.set(Array, i, Item);
		}
	}
").

%-----------------------------------------------------------------------------%

:- pragma foreign_decl("C", "
void ML_shrink_array(MR_ArrayPtr array, MR_ArrayPtr old_array,
	MR_Integer array_size);
").

:- pragma foreign_code("C", "
/*
** The caller is responsible for allocating the storage for the new array.
** This routine does the job of copying the old array elements to the
** new array and deallocating the old array.
*/
void
ML_shrink_array(MR_ArrayPtr array, MR_ArrayPtr old_array,
	MR_Integer array_size)
{
	MR_Integer i;

	array->size = array_size;
	for (i = 0; i < array_size; i++) {
		array->elements[i] = old_array->elements[i];
	}

	/*
	** since the mode on the old array is `array_di', it is safe to
	** deallocate the storage for it
	*/
#ifdef MR_CONSERVATIVE_GC
	GC_FREE(old_array);
#endif
}
").

array__shrink(Array0, Size, Array) :-
	OldSize = array__size(Array0),
	( Size > OldSize ->
		error("array__shrink: can't shrink to a larger size")
	; Size = OldSize ->
		Array = Array0
	;
		array__shrink_2(Array0, Size, Array)
	).

:- pred array__shrink_2(array(T), int, array(T)).
:- mode array__shrink_2(array_di, in, array_uo) is det.

:- pragma foreign_proc("C",
	array__shrink_2(Array0::array_di, Size::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	ML_alloc_array(Array, Size + 1, MR_PROC_LABEL);
	ML_shrink_array(Array, Array0, Size);
").

:- pragma foreign_proc("C#",
	array__shrink_2(Array0::array_di, Size::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	Array = System.Array.CreateInstance(
				Array0.GetType().GetElementType(), Size);
	System.Array.Copy(Array0, Array, Size);
").

:- pragma foreign_proc("Java",
	array__shrink_2(Array0::array_di, Size::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array0 == null) {
		Array = null;
	} else {
		java.lang.Class itemClass = java.lang.reflect.Array.
				get(Array0, 0).getClass();
		Array = java.lang.reflect.Array.newInstance(itemClass, Size);
		for (int i = 0; i < Size; i++) {
			java.lang.reflect.Array.set(Array, i,
					java.lang.reflect.Array.get(Array0, i)
					);
		}
	}
").

%-----------------------------------------------------------------------------%

:- pragma foreign_decl("C", "
void ML_copy_array(MR_ArrayPtr array, MR_ConstArrayPtr old_array);
").

:- pragma foreign_code("C", "
/*
** The caller is responsible for allocating the storage for the new array.
** This routine does the job of copying the array elements.
*/
void
ML_copy_array(MR_ArrayPtr array, MR_ConstArrayPtr old_array)
{
	/*
	** Any changes to this function will probably also require
	** changes to deepcopy() in runtime/deep_copy.c.
	*/

	MR_Integer i;
	MR_Integer array_size;

	array_size = old_array->size;
	array->size = array_size;
	for (i = 0; i < array_size; i++) {
		array->elements[i] = old_array->elements[i];
	}
}
").

:- pragma foreign_proc("C",
	array__copy(Array0::array_ui, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	ML_alloc_array(Array, Array0->size + 1, MR_PROC_LABEL);
	ML_copy_array(Array, (MR_ConstArrayPtr) Array0);
").

:- pragma foreign_proc("C",
	array__copy(Array0::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	ML_alloc_array(Array, Array0->size + 1, MR_PROC_LABEL);
	ML_copy_array(Array, (MR_ConstArrayPtr) Array0);
").

:- pragma foreign_proc("C#",
	array__copy(Array0::array_ui, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	// XXX we implement the same as ML_copy_array, which doesn't appear
	// to deep copy the array elements
	Array = System.Array.CreateInstance(
			Array0.GetType().GetElementType(), Array0.Length);
	System.Array.Copy(Array0, Array, Array0.Length);
").

:- pragma foreign_proc("C#",
	array__copy(Array0::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	// XXX we implement the same as ML_copy_array, which doesn't appear
	// to deep copy the array elements
	Array = System.Array.CreateInstance(
			Array0.GetType().GetElementType(), Array0.Length);
	System.Array.Copy(Array0, Array, Array0.Length);
").

:- pragma foreign_proc("Java",
	array__copy(Array0::array_ui, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array0 == null) {
		Array = null;
	} else {
		java.lang.Class itemClass = java.lang.reflect.Array.
				get(Array0, 0).getClass();
		int length = java.lang.reflect.Array.getLength(Array0);
		Array = java.lang.reflect.Array.newInstance(itemClass, length);
		for (int i = 0; i < length; i++) {
			java.lang.reflect.Array.set(Array, i,
					java.lang.reflect.Array.get(Array0, i)
					);
		}
	}
").
:- pragma foreign_proc("Java",
	array__copy(Array0::in, Array::array_uo),
	[will_not_call_mercury, promise_pure, thread_safe],
"
	if (Array0 == null) {
		Array = null;
	} else {
		java.lang.Class itemClass = java.lang.reflect.Array.
				get(Array0, 0).getClass();
		int length = java.lang.reflect.Array.getLength(Array0);
		Array = java.lang.reflect.Array.newInstance(itemClass, length);
		for (int i = 0; i < length; i++) {
			java.lang.reflect.Array.set(Array, i,
					java.lang.reflect.Array.get(Array0, i)
					);
		}
	}
").

%-----------------------------------------------------------------------------%

array(List) = Array :-
	array__from_list(List, Array).

array__from_list([], Array) :-
	array__make_empty_array(Array).
array__from_list(List, Array) :-
	List = [ Head | Tail ],
	list__length(List, Len),
	array__init(Len, Head, Array0),
	array__insert_items(Tail, 1, Array0, Array).

%-----------------------------------------------------------------------------%

:- pred array__insert_items(list(T), int, array(T), array(T)).
:- mode array__insert_items(in, in, array_di, array_uo) is det.

array__insert_items([], _N, Array, Array).
array__insert_items([Head|Tail], N, Array0, Array) :-
	array__set(Array0, N, Head, Array1),
	N1 = N + 1,
	array__insert_items(Tail, N1, Array1, Array).

%-----------------------------------------------------------------------------%

array__to_list(Array, List) :-
	array__bounds(Array, Low, High),
	array__fetch_items(Array, Low, High, List).

%-----------------------------------------------------------------------------%

array__fetch_items(Array, Low, High, List) :-
	List = foldr_0(func(X, Xs) = [X | Xs], Array, [], Low, High).

%-----------------------------------------------------------------------------%

array__bsearch(A, El, Compare, Result) :-
	array__bounds(A, Lo, Hi),
	array__bsearch_2(A, Lo, Hi, El, Compare, Result).

:- pred array__bsearch_2(array(T), int, int, T,
			pred(T, T, comparison_result), maybe(int)).
:- mode array__bsearch_2(in, in, in, in, pred(in, in, out) is det,
				out) is det.
array__bsearch_2(Array, Lo, Hi, El, Compare, Result) :-
	Width = Hi - Lo,

	% If Width < 0, there is no range left.
	( Width < 0 ->
	    Result = no
	;
	    % If Width == 0, we may just have found our element.
	    % Do a Compare to check.
	    ( Width = 0 ->
	        array__lookup(Array, Lo, X),
	        ( call(Compare, El, X, (=)) ->
		    Result = yes(Lo)
	        ;
		    Result = no
	        )
	    ;
	        % Otherwise find the middle element of the range
	        % and check against that.
	        Mid = (Lo + Hi) >> 1,	% `>> 1' is hand-optimized `div 2'.
	        array__lookup(Array, Mid, XMid),
	        call(Compare, XMid, El, Comp),
	        ( Comp = (<),
		    Mid1 = Mid + 1,
		    array__bsearch_2(Array, Mid1, Hi, El, Compare, Result)
	        ; Comp = (=),
		    array__bsearch_2(Array, Lo, Mid, El, Compare, Result)
	        ; Comp = (>),
		    Mid1 = Mid - 1,
		    array__bsearch_2(Array, Lo, Mid1, El, Compare, Result)
	        )
	    )
	).

%-----------------------------------------------------------------------------%

array__map(Closure, OldArray, NewArray) :-
	( array__semidet_lookup(OldArray, 0, Elem0) ->
		array__size(OldArray, Size),
		call(Closure, Elem0, Elem),
		array__init(Size, Elem, NewArray0),
		array__map_2(1, Size, Closure, OldArray,
		NewArray0, NewArray)
	;
		array__make_empty_array(NewArray)
	).

:- pred array__map_2(int, int, pred(T1, T2), array(T1), array(T2), array(T2)).
:- mode array__map_2(in, in, pred(in, out) is det, in, array_di, array_uo)
		is det.

array__map_2(N, Size, Closure, OldArray, NewArray0, NewArray) :-
	( N >= Size ->
		NewArray = NewArray0
	;
		array__lookup(OldArray, N, OldElem),
		Closure(OldElem, NewElem),
		array__set(NewArray0, N, NewElem, NewArray1),
		array__map_2(N + 1, Size, Closure, OldArray,
		NewArray1, NewArray)
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
% Ralph Becket <rwab1@cam.sri.com> 24/04/99
%	Function forms added.

array__make_empty_array = A :-
	array__make_empty_array(A).

array__init(N, X) = A :-
	array__init(N, X, A).

array__min(A) = N :-
	array__min(A, N).

array__max(A) = N :-
	array__max(A, N).

array__size(A) = N :-
	array__size(A, N).

array__lookup(A, N) = X :-
	array__lookup(A, N, X).

array__set(A1, N, X) = A2 :-
	array__set(A1, N, X, A2).

array__slow_set(A1, N, X) = A2 :-
	array__slow_set(A1, N, X, A2).

array__copy(A1) = A2 :-
	array__copy(A1, A2).

array__resize(A1, N, X) = A2 :-
	array__resize(A1, N, X, A2).

array__shrink(A1, N) = A2 :-
	array__shrink(A1, N, A2).

array__from_list(Xs) = A :-
	array__from_list(Xs, A).

array__to_list(A) = Xs :-
	array__to_list(A, Xs).

array__fetch_items(A, N1, N2) = Xs :-
	array__fetch_items(A, N1, N2, Xs).

array__bsearch(A, X, F) = MN :-
	P = ( pred(X1::in, X2::in, C::out) is det :- C = F(X1, X2) ),
	array__bsearch(A, X, P, MN).

array__map(F, A1) = A2 :-
	P = ( pred(X::in, Y::out) is det :- Y = F(X) ),
	array__map(P, A1, A2).

array_compare(A1, A2) = C :-
	array_compare(C, A1, A2).

array__elem(Index, Array) = array__lookup(Array, Index).

'array__elem :='(Index, Array, Value) = array__set(Array, Index, Value).

% ---------------------------------------------------------------------------- %

	% array__sort/1 has type specialised versions for arrays of
	% ints and strings on the expectation that these constitute
	% the common case and are hence worth providing a fast-path.
	%
	% Experiments indicate that type specialisation improves
	% array__sort/1 by a factor of 30-40%.
	%
:- pragma type_spec(array__sort/1, T = int).
:- pragma type_spec(array__sort/1, T = string).

array__sort(A) = samsort_subarray(A, array__min(A), array__max(A)).

%------------------------------------------------------------------------------%

array__random_permutation(A0, A, RS0, RS) :-
	Lo = array__min(A0),
	Hi = array__max(A0),
	Sz = array__size(A0),
	permutation_2(Lo, Lo, Hi, Sz, A0, A, RS0, RS).

:- pred permutation_2(int, int, int, int, array(T), array(T),
		random__supply, random__supply).
:- mode permutation_2(in, in, in, in, array_di, array_uo, mdi, muo) is det.

permutation_2(I, Lo, Hi, Sz, A0, A, RS0, RS) :-
	( if I > Hi then
		A  = A0,
		RS = RS0
	  else
	  	random__random(R, RS0, RS1),
	  	J  = Lo + (R `rem` Sz),
		A1 = swap_elems(A0, I, J),
		permutation_2(I + 1, Lo, Hi, Sz, A1, A, RS1, RS)
	).

%------------------------------------------------------------------------------%

:- func swap_elems(array(T), int, int) = array(T).
:- mode swap_elems(array_di, in, in) = array_uo is det.

swap_elems(A0, I, J) = A :-
	XI = A0 ^ elem(I),
	XJ = A0 ^ elem(J),
	A  = ((A0 ^ elem(I) := XJ)
		  ^ elem(J) := XI).

% ---------------------------------------------------------------------------- %

array__foldl(Fn, A, X) =
	foldl_0(Fn, A, X, array__min(A), array__max(A)).

:- func foldl_0(func(T1, T2) = T2, array(T1), T2, int, int) = T2.
:- mode foldl_0(func(in, in) = out is det, array_ui, in, in, in) = out is det.
:- mode foldl_0(func(in, in) = out is det, in, in, in, in) = out is det.
:- mode foldl_0(func(in, di) = uo is det, array_ui, di, in, in) = uo is det.
:- mode foldl_0(func(in, di) = uo is det, in, di, in, in) = uo is det.

foldl_0(Fn, A, X, I, Max) =
	( if Max < I	then X
			else foldl_0(Fn, A, Fn(A ^ elem(I), X), I + 1, Max)
	).

% ---------------------------------------------------------------------------- %

array__foldr(Fn, A, X) =
	foldr_0(Fn, A, X, array__min(A), array__max(A)).

:- func foldr_0(func(T1, T2) = T2, array(T1), T2, int, int) = T2.
:- mode foldr_0(func(in, in) = out is det, array_ui, in, in, in) = out is det.
:- mode foldr_0(func(in, in) = out is det, in, in, in, in) = out is det.
:- mode foldr_0(func(in, di) = uo is det, array_ui, di, in, in) = uo is det.
:- mode foldr_0(func(in, di) = uo is det, in, di, in, in) = uo is det.

foldr_0(Fn, A, X, Min, I) =
	( if I < Min	then X
			else foldr_0(Fn, A, Fn(A ^ elem(I), X), Min, I - 1)
	).

% ---------------------------------------------------------------------------- %
% ---------------------------------------------------------------------------- %

	% SAMsort (smooth applicative merge) invented by R.A. O'Keefe.
	%
	% SAMsort is a mergesort variant that works by identifying contiguous
	% monotonic sequences and merging them, thereby taking advantage of
	% any existing order in the input sequence.
	%

:- func samsort_subarray(array(T), int, int) = array(T).
:- mode samsort_subarray(array_di, in, in) = array_uo is det.

:- pragma type_spec(samsort_subarray/3, T = int).
:- pragma type_spec(samsort_subarray/3, T = string).

samsort_subarray(A0, Lo, Hi) = A :-
	samsort_up(0, A0, _, array__copy(A0), A, Lo, Hi, Lo).

:- pred samsort_up(int, array(T), array(T), array(T), array(T), int, int, int).
:- mode samsort_up(in, array_di, array_uo, array_di, array_uo, in, in, in)
	is det.

:- pragma type_spec(samsort_up/8, T = int).
:- pragma type_spec(samsort_up/8, T = string).

	% Precondition:
	%   We are N levels from the bottom (leaf nodes) of the tree.
	%   A0 is sorted from Lo .. I - 1.
	%   A0 and B0 are identical from I .. Hi.
	% Postcondition:
	%   B is sorted from Lo .. Hi.
	%
samsort_up(N, A0, A, B0, B, Lo, Hi, I) :-
	( if I > Hi then
		A = A0,
		B = B0
	else if N > 0 then
		samsort_down(N - 1, B0, B1, A0, A1, I, Hi, J),
			% A1 is sorted from I .. J - 1.
			% A1 and B1 are identical from J .. Hi.
		B2 = merge_subarrays(A1, B1, Lo, I - 1, I, J - 1, Lo),
		A2 = A1,
			% B2 is sorted from Lo .. J - 1.
		samsort_up(N + 1, B2, B, A2, A, Lo, Hi, J)
	else /* N = 0, I = Lo */
		copy_run_ascending(A0, B0, B1, Lo, Hi, J),
			% B1 is sorted from Lo .. J - 1.
		samsort_up(N + 1, B1, B, A0, A, Lo, Hi, J)
	).

:- pred samsort_down(int,array(T),array(T),array(T),array(T),int,int,int).
:- mode samsort_down(in, array_di, array_uo, array_di, array_uo, in, in, out)
	is det.

:- pragma type_spec(samsort_down/8, T = int).
:- pragma type_spec(samsort_down/8, T = string).

	% Precondition:
	%   We are N levels from the bottom (leaf nodes) of the tree.
	%   A0 and B0 are identical from Lo .. Hi.
	% Postcondition:
	%   B is sorted from Lo .. I - 1.
	%   A and B are identical from I .. Hi.
	%
samsort_down(N, A0, A, B0, B, Lo, Hi, I) :-
	( if Lo > Hi then
		A = A0,
		B = B0,
		I = Lo
	else if N > 0 then
		samsort_down(N - 1, B0, B1, A0, A1, Lo, Hi, J),
		samsort_down(N - 1, B1, B2, A1, A2, J,  Hi, I),
			% A2 is sorted from Lo .. J - 1.
			% A2 is sorted from J  .. I - 1.
		A = A2,
		B = merge_subarrays(A2, B2, Lo, J - 1, J, I - 1, Lo)
			% B is sorted from Lo .. I - 1.
	else
		A = A0,
		copy_run_ascending(A0, B0, B, Lo, Hi, I)
			% B is sorted from Lo .. I - 1.
	).

%------------------------------------------------------------------------------%

:- pred copy_run_ascending(array(T), array(T), array(T), int, int, int).
:- mode copy_run_ascending(array_ui, array_di, array_uo, in, in, out) is det.

:- pragma type_spec(copy_run_ascending/6, T = int).
:- pragma type_spec(copy_run_ascending/6, T = string).

copy_run_ascending(A, B0, B, Lo, Hi, I) :-
	( if Lo < Hi, compare((>), A ^ elem(Lo), A ^ elem(Lo + 1)) then
		I = search_until((<), A, Lo, Hi),
		B = copy_subarray_reverse(A, B0, Lo, I - 1, I - 1)
	else
		I = search_until((>), A, Lo, Hi),
		B = copy_subarray(A, B0, Lo, I - 1, Lo)
	).

%------------------------------------------------------------------------------%

:- func search_until(comparison_result, array(T), int, int) = int.
:- mode search_until(in, array_ui, in, in) = out is det.

:- pragma type_spec(search_until/4, T = int).
:- pragma type_spec(search_until/4, T = string).

search_until(R, A, Lo, Hi) =
	( if Lo < Hi, not compare(R, A ^ elem(Lo), A ^ elem(Lo + 1)) then
		search_until(R, A, Lo + 1, Hi)
	else
		Lo + 1
	).

%------------------------------------------------------------------------------%

:- func copy_subarray(array(T), array(T), int, int, int) = array(T).
:- mode copy_subarray(array_ui, array_di, in, in, in) = array_uo is det.

:- pragma type_spec(copy_subarray/5, T = int).
:- pragma type_spec(copy_subarray/5, T = string).

copy_subarray(A, B, Lo, Hi, I) =
	( if Lo =< Hi then
		copy_subarray(A, B ^ elem(I) := A ^ elem(Lo),
			Lo + 1, Hi, I + 1)
	else
		B
	).

%------------------------------------------------------------------------------%

:- func copy_subarray_reverse(array(T), array(T), int, int, int) = array(T).
:- mode copy_subarray_reverse(array_ui, array_di, in, in, in) = array_uo is det.

:- pragma type_spec(copy_subarray_reverse/5, T = int).
:- pragma type_spec(copy_subarray_reverse/5, T = string).

copy_subarray_reverse(A, B, Lo, Hi, I) =
	( if Lo =< Hi then
		copy_subarray_reverse(A, B ^ elem(I) := A ^ elem(Lo),
			Lo + 1, Hi, I - 1)
	else
		B
	).

%------------------------------------------------------------------------------%

	% merges the two sorted consecutive subarrays Lo1 .. Hi1 and
	% Lo2 .. Hi2 from A into the subarray starting at I in B.
	%
:- func merge_subarrays(array(T), array(T), int, int, int, int, int) = array(T).
:- mode merge_subarrays(array_ui, array_di, in, in, in, in, in) = array_uo
	is det.

:- pragma type_spec(merge_subarrays/7, T = int).
:- pragma type_spec(merge_subarrays/7, T = string).

merge_subarrays(A, B0, Lo1, Hi1, Lo2, Hi2, I) = B :-
	( if Lo1 > Hi1 then
		B = copy_subarray(A, B0, Lo2, Hi2, I)
	else if Lo2 > Hi2 then
		B = copy_subarray(A, B0, Lo1, Hi1, I)
	else
		X1 = A ^ elem(Lo1),
		X2 = A ^ elem(Lo2),
		compare(R, X1, X2),
		(
			R = (<),
			B = merge_subarrays(A, B0^elem(I) := X1,
				Lo1+1, Hi1, Lo2, Hi2, I+1)
		;
			R = (=),
			B = merge_subarrays(A, B0^elem(I) := X1,
				Lo1+1, Hi1, Lo2, Hi2, I+1)
		;
			R = (>),
			B = merge_subarrays(A, B0^elem(I) := X2,
				Lo1, Hi1, Lo2+1, Hi2, I+1)
		)
	).

%------------------------------------------------------------------------------%

	% throw an exception indicating an array bounds error
:- pred out_of_bounds_error(array(T), int, string).
:- mode out_of_bounds_error(array_ui, in, in) is erroneous.
:- mode out_of_bounds_error(in, in, in) is erroneous.

	% Note: we deliberately do not include the array element type name
	% in the error message here, for performance reasons:
	% using the type name could prevent the compiler from optimizing
	% away the construction of the type_info in the caller,
	% because it would prevent unused argument elimination.
	% Performance is important here, because array__set and array__lookup
	% are likely to be used in the inner loops of performance-critical
	% applications.
out_of_bounds_error(Array, Index, PredName) :-
	array__bounds(Array, Min, Max),
	throw(array__index_out_of_bounds(
		string__format("%s: index %d not in range [%d, %d]",
			[s(PredName), i(Index), i(Min), i(Max)]))).

%-----------------------------------------------------------------------------%

array__least_index(A) = array__min(A).

array__greatest_index(A) = array__max(A).

%------------------------------------------------------------------------------%
%------------------------------------------------------------------------------%
