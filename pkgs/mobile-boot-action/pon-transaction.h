/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef MOBILE_PON_TRANSACTION_H
#define MOBILE_PON_TRANSACTION_H

struct mobile_pon_ops {
	int (*read)(void *context, unsigned char *value);
	int (*write)(void *context, unsigned char value);
	int (*reset)(void *context);
	void *context;
};

/* Only the matched PON spare byte is accessible through these callbacks. */
static inline int mobile_pon_execute(const struct mobile_pon_ops *ops, unsigned int action,
				     struct mobile_action_result *result)
{
	unsigned char old, wanted, actual;
	int ret;

	if (action != MOBILE_ACTION_BOOTLOADER && action != MOBILE_ACTION_RECOVERY)
		return -EINVAL;
	result->stage = MOBILE_STAGE_READ;
	ret = ops->read(ops->context, &old);
	if (ret)
		goto failed;
	wanted = (old & 1) | (action == MOBILE_ACTION_BOOTLOADER ? 4 : 2);
	result->stage = MOBILE_STAGE_WRITE;
	ret = ops->write(ops->context, wanted);
	if (ret)
		goto restore;
	result->stage = MOBILE_STAGE_VERIFY;
	ret = ops->read(ops->context, &actual);
	if (!ret && actual != wanted)
		ret = -EIO;
	if (ret)
		goto restore;
	result->stage = MOBILE_STAGE_RESET;
	ret = ops->reset(ops->context);
	/* PSCI SYSTEM_RESET must not return, even with a success value. */
restore:
	result->operation_status = ret;
	result->restore_attempted = 1;
	result->restore_status = ops->write(ops->context, old);
	if (!result->restore_status) {
		result->restore_status = ops->read(ops->context, &actual);
		if (!result->restore_status && actual != old)
			result->restore_status = -EIO;
	}
	return ret ? ret : -EIO;
failed:
	result->operation_status = ret;
	return ret;
}
#endif
