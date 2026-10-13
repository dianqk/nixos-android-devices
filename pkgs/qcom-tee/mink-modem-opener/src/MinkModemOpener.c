// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause-Clear
//
// From minkipc v1.2.10 mink_platform/HLOS/minkdaemon/src/MinkModemOpener.cpp.
// Local changes:
// - Without the HLOS Mink daemon's TEnv, open() asks the QTEE client
//   environment directly (IClientEnv_open), as the vendor ssgtzd does.
// - register()/unregister() follow the vendor ssgtzd that ships with the 2024
//   modem firmware instead of minkipc's single-client table: each modem client
//   (diag, GNSS, Smart Transmit, ...) registers its own object and keeps it
//   until it unregisters it, up to 10 at a time (then Object_ERROR_NOSLOTS).
//   minkipc closes slot 0 on every register, which drops the previous
//   client's object as soon as a second modem task connects.

#include <pthread.h>
#include <stdint.h>
#include <time.h>
#include "CTunnelInvokeMgr.h"
#include "IClientEnv.h"
#include "IMinkModemOpener_invoke.h"
#include "MinkModemOpener.h"
#include "Utils.h"
#include "heap.h"
#include "object.h"
#include "trace.h"

#define MAX_MODEM_CLIENTS 10

typedef struct {
    int32_t refs;
    pthread_mutex_t mutex;
    Object clients[MAX_MODEM_CLIENTS];
    size_t count;
    Object clientEnv;
} MinkModemOpener;

static int32_t MinkModemOpener_retain(MinkModemOpener *me)
{
    vm_osal_atomic_add(&me->refs, 1);

    return Object_OK;
}

static int32_t MinkModemOpener_release(MinkModemOpener *me)
{
    if (vm_osal_atomic_add(&me->refs, -1) == 0) {
        LOG_MSG("MinkModemOpener_release\n");
        for (size_t i = 0; i < MAX_MODEM_CLIENTS; i++)
            Object_ASSIGN_NULL(me->clients[i]);
        Object_ASSIGN_NULL(me->clientEnv);
        pthread_mutex_destroy(&me->mutex);
        HEAP_FREE_PTR(me);
    }

    return Object_OK;
}

static int32_t MinkModemOpener_open(MinkModemOpener *me, uint32_t id_val, Object *obj_ptr)
{
    struct timespec t0, t1;
    int32_t ret;

    switch (id_val) {
        case CTunnelInvokeMgr_UID:
            LOG_MSG("calling IClientEnv_open(%u)\n", id_val);
            clock_gettime(CLOCK_MONOTONIC, &t0);
            ret = IClientEnv_open(me->clientEnv, id_val, obj_ptr);
            clock_gettime(CLOCK_MONOTONIC, &t1);
            LOG_MSG("IClientEnv_open(%u) returned %d after %ld ms\n", id_val, ret,
                    (long)((t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000));
            return ret;
        default:
            LOG_ERR("MinkModemOpener_open: unsupported uid %u\n", id_val);
            break;
    }

    return Object_ERROR;
}

static int32_t MinkModemOpener_register(MinkModemOpener *me, Object obj, int32_t *id)
{
    char desc[96];
    int32_t index = -1;
    size_t count;

    if (Object_isNull(obj)) {
        LOG_ERR("MinkModemOpener_register: null object\n");
        return Object_ERROR;
    }

    pthread_mutex_lock(&me->mutex);
    if (me->count < MAX_MODEM_CLIENTS) {
        for (int32_t i = 0; i < MAX_MODEM_CLIENTS; i++) {
            if (Object_isNull(me->clients[i])) {
                Object_INIT(me->clients[i], obj);
                me->count++;
                index = i;
                break;
            }
        }
    }
    count = me->count;
    pthread_mutex_unlock(&me->mutex);

    Trace_describe(obj, desc, sizeof(desc));
    if (index < 0) {
        LOG_ERR("MinkModemOpener_register: %zu clients registered, refusing %s\n", count, desc);
        return Object_ERROR_NOSLOTS;
    }

    *id = index;
    LOG_MSG("MinkModemOpener_register, return index = %d (%s, %zu clients)\n", index, desc,
            count);
    return Object_OK;
}

static int32_t MinkModemOpener_unregister(MinkModemOpener *me, int32_t id)
{
    Object obj = Object_NULL;
    size_t count;

    if (id < 0 || id >= MAX_MODEM_CLIENTS) {
        LOG_ERR("MinkModemOpener_unregister: invalid index %d\n", id);
        return Object_ERROR;
    }

    pthread_mutex_lock(&me->mutex);
    obj = me->clients[id];
    if (!Object_isNull(obj)) {
        me->clients[id] = Object_NULL;
        me->count--;
    }
    count = me->count;
    pthread_mutex_unlock(&me->mutex);

    if (Object_isNull(obj)) {
        LOG_ERR("MinkModemOpener_unregister: index %d is not registered\n", id);
        return Object_ERROR;
    }

    LOG_MSG("MinkModemOpener_unregister, receive index = %d (%zu clients left)\n", id, count);
    Object_release(obj);
    return Object_OK;
}

static IMinkModemOpener_DEFINE_INVOKE(MinkModemOpener_invoke, MinkModemOpener_, MinkModemOpener *);

int32_t MinkModemOpener_new(Object clientEnv, Object *objOut)
{
    MinkModemOpener *me = HEAP_ZALLOC_TYPE(MinkModemOpener);
    if (!me) {
        LOG_ERR("Memory allocation for mink modem opener failed\n");
        return Object_ERROR_MEM;
    }

    me->refs = 1;
    pthread_mutex_init(&me->mutex, NULL);
    Object_INIT(me->clientEnv, clientEnv);
    *objOut = (Object){MinkModemOpener_invoke, me};

    return Object_OK;
}
