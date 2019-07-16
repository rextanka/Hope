#ifndef OP_H
#define OP_H

#include "defs.h"
#include "newstring.h"
#include "table.h"

/*
 *	Associativity and precedence of operators.
 *	The values of the ASSOC_ constants must be in the order that
 *	the binary operators are generated by Mult-op.awk (qv),
 *	so that the calculation in lookup() in yylex.c will work.
 */
typedef enum {
	ASSOC_LEFT,
	ASSOC_RIGHT,
/* count of the above */
	NUM_ASSOC
} Assoc;

typedef	struct {
	TabElt	op_linkage;
	short	op_prec;
	Assoc	op_assoc;
} Op;

#define	op_name	op_linkage.t_name

extern	void	op_declare(String name, int prec, Assoc assoc);
extern	Op	*op_lookup(String name);

/*
 * The range of precedences of user-defined infix operators.
 */
#define	MINPREC		1
#define	MAXPREC		9

#endif
