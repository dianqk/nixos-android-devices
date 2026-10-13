// Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
// SPDX-License-Identifier: BSD-3-Clause-Clear

#ifndef __MINKMODEMOPENER_H
#define __MINKMODEMOPENER_H

#include "object.h"

/* clientEnv: QTEE client environment object (IClientEnv). */
int32_t MinkModemOpener_new(Object clientEnv, Object *objOut);

#endif  // __MINKMODEMOPENER_H
