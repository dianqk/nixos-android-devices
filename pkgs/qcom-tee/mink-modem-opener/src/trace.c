// SPDX-License-Identifier: BSD-3-Clause

#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "msforwarder.h"
#include "object.h"
#include "trace.h"

bool gTraceEnabled;

/* Input buffers up to this size are logged in hex (UIDs, IDs, lengths). */
#define TRACE_HEX_MAX 8
#define TRACE_LINE 1024
#define TRACE_DESC 96

typedef struct {
	atomic_int refs;
	unsigned id;
	Object inner;
	char name[64];
} TraceObj;

static atomic_uint gNextId = 1;

static int32_t TraceObj_invoke(ObjectCxt cxt, ObjectOp op, ObjectArg *args, ObjectCounts k);

static TraceObj *TraceObj_from(Object o)
{
	return o.invoke == TraceObj_invoke ? (TraceObj *)o.context : NULL;
}

void Trace_log(const char *fmt, ...)
{
	char line[TRACE_LINE];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	printf("trace[%ld] %s\n", (long)syscall(SYS_gettid), line);
}

void Trace_describe(Object o, char *buf, size_t len)
{
	TraceObj *t;
	MSForwarder *f;

	if (Object_isNull(o))
		snprintf(buf, len, "null");
	else if ((t = TraceObj_from(o)))
		snprintf(buf, len, "#%u(%s)", t->id, t->name);
	else if ((f = MSForwarderFromObject(o)))
		snprintf(buf, len, "modem-handle-%d", f->handle);
	else
		snprintf(buf, len, "local-%p", o.context);
}

Object Trace_wrap(Object inner, const char *fmt, ...)
{
	char desc[TRACE_DESC];
	TraceObj *t;
	va_list ap;

	if (!gTraceEnabled || Object_isNull(inner) || TraceObj_from(inner))
		return inner;

	t = calloc(1, sizeof(*t));
	if (!t) {
		Trace_log("cannot trace an object: out of memory");
		return inner;
	}
	atomic_init(&t->refs, 1);
	t->id = atomic_fetch_add(&gNextId, 1);
	t->inner = inner;
	va_start(ap, fmt);
	vsnprintf(t->name, sizeof(t->name), fmt, ap);
	va_end(ap);

	Trace_describe(inner, desc, sizeof(desc));
	Trace_log("new #%u(%s) -> %s", t->id, t->name, desc);
	return (Object){ TraceObj_invoke, t };
}

static long elapsed_us(const struct timespec *t0)
{
	struct timespec t1;

	clock_gettime(CLOCK_MONOTONIC, &t1);
	return (t1.tv_sec - t0->tv_sec) * 1000000L + (t1.tv_nsec - t0->tv_nsec) / 1000;
}

/* Appends " name=<size>[:hex]" for each buffer in [first, first + n). */
static void describe_buffers(char *line, size_t len, const char *name, const ObjectArg *args,
			     size_t first, size_t n, bool hex)
{
	for (size_t i = 0; i < n; i++) {
		const ObjectBuf *b = &args[first + i].b;
		size_t used = strlen(line);

		snprintf(line + used, len - used, " %s%zu=%zu", name, i, b->size);
		if (hex && b->ptr && b->size > 0 && b->size <= TRACE_HEX_MAX) {
			for (size_t j = 0; j < b->size; j++) {
				used = strlen(line);
				snprintf(line + used, len - used, "%s%02x", j ? "" : ":",
					 ((const uint8_t *)b->ptr)[j]);
			}
		}
	}
}

static void describe_objects(char *line, size_t len, const char *name, const ObjectArg *args,
			     size_t first, size_t n)
{
	char desc[TRACE_DESC];

	for (size_t i = 0; i < n; i++) {
		size_t used = strlen(line);

		Trace_describe(args[first + i].o, desc, sizeof(desc));
		snprintf(line + used, len - used, " %s%zu=%s", name, i, desc);
	}
}

static int32_t TraceObj_invoke(ObjectCxt cxt, ObjectOp op, ObjectArg *args, ObjectCounts k)
{
	TraceObj *me = cxt;
	ObjectOp method = ObjectOp_methodID(op);
	size_t total = ObjectCounts_total(k);
	size_t iBI = ObjectCounts_indexBI(k), nBI = ObjectCounts_numBI(k);
	size_t iBO = ObjectCounts_indexBO(k), nBO = ObjectCounts_numBO(k);
	size_t iOI = ObjectCounts_indexOI(k), nOI = ObjectCounts_numOI(k);
	size_t iOO = ObjectCounts_indexOO(k), nOO = ObjectCounts_numOO(k);
	ObjectArg a[ObjectCounts_maxBI + ObjectCounts_maxBO + ObjectCounts_maxOI +
		    ObjectCounts_maxOO];
	Object temps[ObjectCounts_maxOI];
	size_t nTemps = 0;
	char line[TRACE_LINE];
	struct timespec t0;
	int32_t rc;

	if (method == Object_OP_retain) {
		atomic_fetch_add(&me->refs, 1);
		return Object_OK;
	}
	if (method == Object_OP_release) {
		if (atomic_fetch_sub(&me->refs, 1) == 1) {
			Trace_log("release #%u(%s)", me->id, me->name);
			Object_release(me->inner);
			free(me);
		}
		return Object_OK;
	}

	memcpy(a, args, total * sizeof(ObjectArg));
	for (size_t i = 0; i < nOI; i++) {
		Object o = args[iOI + i].o;
		TraceObj *t = TraceObj_from(o);

		if (t) {
			a[iOI + i].o = t->inner;
		} else if (!Object_isNull(o)) {
			Object_retain(o);
			temps[nTemps] = Trace_wrap(o, "in%zu of #%u m%u", i, me->id, (unsigned)method);
			a[iOI + i].o = temps[nTemps++];
		}
	}

	snprintf(line, sizeof(line), "> #%u(%s) m%u op=0x%x k=0x%x", me->id, me->name,
		 (unsigned)method, (unsigned)op, (unsigned)k);
	describe_buffers(line, sizeof(line), "bi", args, iBI, nBI, true);
	describe_objects(line, sizeof(line), "oi", a, iOI, nOI);
	Trace_log("%s", line);

	clock_gettime(CLOCK_MONOTONIC, &t0);
	rc = Object_invoke(me->inner, op, a, k);
	long us = elapsed_us(&t0);

	for (size_t i = 0; i < nBO; i++)
		args[iBO + i].b.size = a[iBO + i].b.size;
	for (size_t i = 0; i < nOO; i++) {
		Object o = a[iOO + i].o;
		TraceObj *t = TraceObj_from(o);

		if (Object_isOK(rc) && t) {
			Object inner = t->inner;

			Object_retain(inner);
			Object_release(o);
			o = inner;
		} else if (Object_isOK(rc)) {
			o = Trace_wrap(o, "out%zu of #%u m%u", i, me->id, (unsigned)method);
		}
		args[iOO + i].o = o;
	}
	for (size_t i = 0; i < nTemps; i++)
		Object_release(temps[i]);

	snprintf(line, sizeof(line), "< #%u(%s) m%u rc=%d %ld.%03ldms", me->id, me->name,
		 (unsigned)method, rc, us / 1000, us % 1000);
	if (Object_isOK(rc)) {
		describe_buffers(line, sizeof(line), "bo", args, iBO, nBO, false);
		describe_objects(line, sizeof(line), "oo", args, iOO, nOO);
	}
	Trace_log("%s", line);
	return rc;
}
