// SPDX-License-Identifier: BSD-3-Clause
//
// Without REMOTE_SHAREMM no WrappedMemparcel objects exist; ObjectTable.c
// still asks about them.

#include <stdbool.h>
#include "object.h"

bool isWrappedMemparcel(Object obj);

bool isWrappedMemparcel(Object obj)
{
	(void)obj;
	return false;
}
