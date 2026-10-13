/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * Definitions MinkSocket takes from the unpublished Android Mink headers.
 * Values match the vendor libminksocket_vendor.so (handle 0x3ff is checked in
 * isPrimordialOrPrimordialFwd; 0xfffd is the third reserved method).
 */
#pragma once
#include "object.h"
#ifndef GENERIC_HANDLE
#define GENERIC_HANDLE 0
#endif
#ifndef PRIMORDIAL_HANDLE
#define PRIMORDIAL_HANDLE 0x3ff
#endif
#ifndef Object_OP_unwrapFd
#define Object_OP_unwrapFd (ObjectOp_METHOD_MASK - 2)
#endif

#ifndef Object_unwrapFd
static inline int32_t Object_unwrapFd(Object o, int *fd)
{
	ObjectArg a[1];
	a[0].b = (ObjectBuf){ fd, sizeof(int) };
	return Object_invoke(o, Object_OP_unwrapFd, a, ObjectCounts_pack(0, 1, 0, 0));
}
#endif
