%{
#include "defs.h"
#include "memory.h"
#include "typevar.h"
#include "op.h"
#include "newstring.h"
#include "module.h"
#include "expr.h"
#include "deftype.h"
#include "cons.h"
#include "eval.h"
#include "error.h"
#include "text.h"
%}

%token	TYPEVAR ABSTYPE DATA TYPESYM
%token	DEC INFIX INFIXR USES PRIVATE
%token	DISPLAY SAVE WRITE TO EXIT EDIT
%token	DEFEQ	/* == */
%token	OR	/* ++ */
%token	VALOF	/* --- */
%token	IS	/* <= */
%token	GIVES	/* => */
%token	THEN
%token	FORALL
%token	MODSYM PUBCONST PUBFUN PUBTYPE

/*
 * Operator precedence stuff.  Notes:
 * - Some versions of Hope allow an optional END on a lambda expression.
 *   It gets grabbed by the nearest LAMBDA.  Pretty useless, but a
 *   nuisance to implement: see END, optend.
 * - Infix binary operators are implemented by a series of left- and
 *   right- associative tokens, all represented here by the symbol BINARY.
 *   This file is fed through the sed scripts
 *	op.sed		replicate all lines or grammar rules containing
 *			that symbol (which I won't name again),
 *	Assoc.sed	change each copy of the %token line for that
 *			symbol into a %left or %right as appropriate,
 *   and then into yacc.
 *   The file op.sed is itself generated by Mult-op.awk from op.h.
 *   All this is done automatically by the Makefile.
 * - Application, denoted by juxtaposition, is implemented by a pseudo-
 *   token APPLY.  Any token which could begin an expression must be
 *   given the same precedence.  Here application is left-associative,
 *   and binds more tightly than anything else.
 */

/* weakest precedence */
%right	END
%left	MU
 
%right	','
%right	'|'	/* i.e. lambda expressions */
%left	IN	/* i.e. let/letrec expressions */
%left	WHERE WHEREREC
%left	ELSE	/* i.e. if expressions */

%token	BINARY

%left	APPLY IDENT NUMBER LITERAL CHAR LET LETREC IF LAMBDA '(' '[' NONOP

%nonassoc ALWAYS_REDUCE
/* strongest precedence */

%union {
	Num	numval;
	int	intval;
	Text	*textval;
	String	strval;
	Natural	charval;
	Type	*type;
	TypeList *typelist;
	DefType	*deftype;
	QType	*qtype;
	Expr	*expr;
	Branch	*branch;
	Cons	*cons;
}

%type	<numval>	NUMBER
%type	<intval>	precedence infixlist infixrlist
%type	<strval>	IDENT name ident binop
%type	<strval>	BINARY
%type	<textval>	LITERAL
%type	<charval>	CHAR
%type	<type>		tv
%type	<typelist>	tvargs tvlist tvpair
%type	<deftype>	newtype
%type	<cons>		constype constypelist
%type	<type>		type typearg
%type	<qtype>		decl simple_decl q_type
%type	<typelist>	typeargs typelist typepair
%type	<expr>		tuple
%type	<expr>		formals
%type	<expr>		expr exprlist exprbody
%type	<branch>	rulelist

%{
/* Traditional yacc provides a global variable yyerrflag, which is
   non-zero when the parser is attempting to recover from an error.
   We use this for simple error recovery for interactive sessions
   in yylex().
 */
extern	int	yyerrflag;

global Bool
recovering(void)
{
	return yyerrflag != 0;
}

#ifdef	YYBISON
/* Bison defines a corresponding variable yyerrstatus local to
   yyparse().  To kludge around this, the Makefile comments out
   the local definition, and we supply a global one.
 */
int	yyerrflag;
#define yyerrstatus yyerrflag
#endif
%}

%%

lines	:	lines line	{ erroneous = FALSE; }
	|	/* empty */	{ erroneous = FALSE; }
	;

line	:	cmd ';'		{ clean_slate(); mod_fetch(); }
	|	error ';'	{ clean_slate(); yyerrok; }
	;

cmd	:	TYPEVAR newtvlist
	|	INFIX infixlist	{ preserve(); }
	|	INFIXR infixrlist
				{ preserve(); }
	|	ABSTYPE abstypelist
	|	TYPESYM newtype DEFEQ type
				{ type_syn($2, $4); }
	|	DATA newtype DEFEQ constypelist
				{ decl_type($2, $4); }
	|	PRIVATE		{ mod_private(); }
	|	DEC decl
	|	simple_decl	{;}	/* abbreviated form */
	|	VALOF expr IS exprbody
				{ def_value($2, $4); }
	|	expr IS exprbody	/* abbreviated form */
				{ def_value($1, $3); }
	|	expr DEFEQ exprbody	/* variant abbreviated form */
				{ def_value($1, $3); }
	|	exprbody	{ eval_expr($1); }
	|	WRITE expr	{ wr_expr($2, (const char *)0); }
	|	WRITE expr TO LITERAL
				{ wr_expr($2, (const char *)($4->t_start)); }
	|	DISPLAY		{ display(); }
	|	USES uselist	{ preserve(); }
	|	SAVE ident	{ mod_save($2); }
	|	EDIT		{ edit((String)0); }
	|	EDIT ident	{ edit($2); }
	|	EXIT		{ YYACCEPT; }
	|	MODSYM ident
	|	PUBCONST idlist
	|	PUBFUN idlist
	|	PUBTYPE idlist
	|	END
	|	/* empty */
	;

idlist	:	idlist ',' ident
	|	ident		{;}
	;

newtvlist:	newtv
	|	newtvlist ',' newtv
	;

newtv	:	ident		{ tv_declare($1); }
	;

infixlist:	IDENT ':' precedence
				{ op_declare($1, $3, ASSOC_LEFT); $$ = $3; }
	|	IDENT ',' infixlist
				{ op_declare($1, $3, ASSOC_LEFT); $$ = $3; }
	;

infixrlist:	IDENT ':' precedence
				{ op_declare($1, $3, ASSOC_RIGHT); $$ = $3; }
	|	IDENT ',' infixrlist
				{ op_declare($1, $3, ASSOC_RIGHT); $$ = $3; }
	;

precedence:	NUMBER		{ $$ = (int)$1; }
	;

uselist	:	use
	|	uselist ',' use
	;

use	:	ident		{ mod_use($1); }
	;

abstypelist :	abstypelist ',' abstype
	|	abstype
	;

abstype	:	newtype		{ abstype($1); }
	;

newtype	:	ident tvargs	{ $$ = new_deftype($1, FALSE, $2); }
	|	ident '(' tv ')'
				{ $$ = new_deftype($1, FALSE,
						cons_type($3, NULL)); }
	|	ident '(' tvpair ')'
				{ $$ = new_deftype($1, TRUE, $3); }
	|	tv BINARY tv	{ $$ = new_deftype($2, TRUE,
					cons_type($1,
					    cons_type($3,
						(TypeList *)NULL))); }
	;

tvargs	:	/* empty */	{ $$ = NULL; }
	|	tv tvargs	{ $$ = cons_type($1, $2); }
	;

tvlist	:	tv		{ $$ = cons_type($1, (TypeList *)NULL); }
	|	tvpair		{ $$ = $1; }
	;

tvpair	:	tv ',' tvlist	{ $$ = cons_type($1, $3); }
	;

tv	:	ident		{ $$ = new_tv($1); }
	;

constypelist:	constype	{ $$ = alt_cons($1, (Cons *)NULL); }
	|	constype OR constypelist
				{ $$ = alt_cons($1, $3); }
	;

/*
 *	A constype has similar syntax to a type, but the topmost
 *	constructor is interpreted as a data constructor.
 */
constype:	ident typeargs		%prec IDENT
				{ $$ = constructor($1, FALSE, $2); }
	|	ident '(' typepair ')'
				{ $$ = constructor($1, TRUE, $3); }
	|	type BINARY type
				{ $$ = constructor($2, TRUE,
					cons_type($1,
						cons_type($3,
							(TypeList *)NULL))); }
	;


type	:	ident typeargs		%prec IDENT
				{ $$ = new_type($1, FALSE, $2); }
	|	ident '(' typepair ')'
				{ $$ = new_type($1, TRUE, $3); }
	|	type BINARY type
				{ $$ = new_type($2, TRUE,
					cons_type($1,
						cons_type($3,
							(TypeList *)NULL))); }
	|	MU mu_tv GIVES type		%prec MU
				{ $$ = mu_type($4); }
	|	'(' type ')'	{ $$ = $2; }
	;

typeargs:	/* empty */	{ $$ = (TypeList *)NULL; }
	|	typearg typeargs
				{ $$ = cons_type($1, $2); }
	;

typearg:	ident		{ $$ = new_type($1, FALSE,
						(TypeList *)NULL); }
	|	'(' type ')'	{ $$ = $2; }
	;

typelist:	type		{ $$ = cons_type($1, (TypeList *)NULL); }
	|	typepair	{ $$ = $1; }
	;

typepair:	type ',' typelist
				{ $$ = cons_type($1, $3); }
	;

mu_tv	:	ident		{ enter_mu_tv($1); }
	;

decl	:	simple_decl	{ $$ = $1; }
	|	name ',' decl	{ decl_value($1, $3); $$ = $3; }
	;

simple_decl:	name ':' q_type	{ decl_value($1, $3); $$ = $3; }
	;

q_type	:	start_dec type	{ $$ = qualified_type($2); }
	;

start_dec:	/* empty */	{ start_dec_type(); }
	;

tuple	:	ident		{ $$ = id_expr($1); }
	|	tuple ',' tuple	{ $$ = pair_expr($1, $3); }
	|	'(' tuple ')'	{ $$ = $2; }
	;

expr	:	ident		{ $$ = id_expr($1); }
	|	NUMBER		{ $$ = num_expr($1); }
	|	LITERAL		{ $$ = text_expr($1->t_start, $1->t_length); }
	|	CHAR		{ $$ = char_expr($1); }
	|	'(' expr binop ')'
				{ $$ = presection($3, $2); }
	|	'(' binop expr ')'
				{ $$ = postsection($2, $3); }
	|	'(' exprbody ')'
				{ $$ = $2; }
	|	'[' exprlist ']'
				{ $$ = $2; }
	|	'[' ']'		{ $$ = e_nil; }
	|	expr expr			%prec APPLY
				{ $$ = apply_expr($1, $2); }
	|	expr BINARY expr
				{ $$ = apply_expr(id_expr($2),
						pair_expr($1, $3));
				}
	|	LAMBDA rulelist optend		%prec ALWAYS_REDUCE
				{ $$ = func_expr($2); }
	|	IF expr THEN exprbody ELSE expr
				{ $$ = ite_expr($2, $4, $6); }
	|	LET exprbody DEFEQ exprbody IN expr
				{ $$ = let_expr($2, $4, $6, FALSE); }
	|	LETREC tuple DEFEQ exprbody IN expr
				{ $$ = let_expr($2, $4, $6, TRUE); }
	|	expr WHERE exprbody DEFEQ expr	%prec WHERE
				{ $$ = where_expr($1, $3, $5, FALSE); }
	|	expr WHEREREC tuple DEFEQ expr	%prec WHERE
				{ $$ = where_expr($1, $3, $5, TRUE); }
	| 	MU tuple GIVES expr		%prec MU
				{ $$ = mu_expr($2, $4); }
	;

exprbody:	expr		{ $$ = $1; }
	|	expr ',' exprbody
				{ $$ = pair_expr($1, $3); }
	;

exprlist:	expr		{ $$ = apply_expr(e_cons,
						  pair_expr($1, e_nil));
				}
	|	expr ',' exprlist
				{ $$ = apply_expr(e_cons, pair_expr($1, $3)); }
	;

rulelist:	formals GIVES expr		%prec '|'
				{ $$ = new_branch($1, $3, (Branch *)0); }
	|	formals GIVES expr '|' rulelist
				{ $$ = new_branch($1, $3, $5); }
	;

/*
 * Formal parameters of a LAMBDA: enable one or ther of the following.
 * If the second form is enabled, a LAMBDA will take multiple arguments,
 * but formal parameters will require more parentheses than now, so it is
 * currently disabled to preserve backward compatability.
 * If it is enabled, the value of PREC_FORMAL in print.h must also be
 * changed, to ensure that the extra parentheses are printed.
 */

formals	:	exprbody	{ $$ = apply_expr((Expr *)0, $1); }
	;

/* *** Disabled: see above
formals	:	expr				%prec ALWAYS_REDUCE
				{ $$ = apply_expr((Expr *)0, $1); }
	|	formals expr			%prec ALWAYS_REDUCE
				{ $$ = apply_expr($1, $2); }
	;
*/

optend	:	/* empty */			%prec END
	|	END
	;

name	:	ident		{ $$ = $1; }
	|	binop		{ $$ = $1; }
	;

ident	:	IDENT		{ $$ = $1; }
	|	'(' binop ')'	{ $$ = $2; }
	|	NONOP binop	{ $$ = $2; }
	;

binop	:	BINARY		{ $$ = $1; }
	;

%%
