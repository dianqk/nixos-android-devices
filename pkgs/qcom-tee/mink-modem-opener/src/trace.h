// SPDX-License-Identifier: BSD-3-Clause
//
// Optional invoke tracing. A traced object forwards every invoke to the
// object it wraps and logs the method, argument counts, small input buffers,
// the result and its duration. Objects that cross a traced object are traced
// as well: output objects are wrapped, input objects are wrapped on their way
// to the wrapped object, and traced objects are unwrapped again so that QTEE
// and MinkSocket always see the original object identities.

#ifndef __MINK_MODEM_OPENER_TRACE_H
#define __MINK_MODEM_OPENER_TRACE_H

#include <stdbool.h>
#include <stddef.h>
#include "object.h"

extern bool gTraceEnabled;

void Trace_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/* Short description of an object for logs: "#<id>(<name>)" for traced
 * objects, "modem-handle-<n>" for MinkSocket forwarders, else its address. */
void Trace_describe(Object o, char *buf, size_t len);

/* Takes over the caller's reference to inner and returns a traced object
 * (or inner itself when tracing is off or inner is null or already traced). */
Object Trace_wrap(Object inner, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

#endif
