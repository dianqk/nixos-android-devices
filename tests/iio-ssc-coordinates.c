/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Exercise the production SSC callback and classifier without a DSP or D-Bus. */
#include "drv-ssc-accel.c"
#include "orientation.h"

static AccelReadings captured;

static void capture(SensorDevice *device, gpointer readings, gpointer user_data)
{
        captured = *(AccelReadings *)readings;
}

int main(void)
{
        AccelVec3 identity[3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
        DrvData drv = { .mount_matrix = identity };
        SensorDevice device = { .priv = &drv, .callback_func = capture };
        const struct {
                float x, y, z;
                OrientationUp orientation;
        } poses[] = {
                {0, 9.81, 0, ORIENTATION_NORMAL},
                {0, -9.81, 0, ORIENTATION_BOTTOM_UP},
                {-9.81, 0, 0, ORIENTATION_LEFT_UP},
                {9.81, 0, 0, ORIENTATION_RIGHT_UP},
                {0.07, 9.23, 3.49, ORIENTATION_NORMAL},
        };
        set_accel_scale(&drv.scale, 1.0);
        for (guint i = 0; i < G_N_ELEMENTS(poses); i++) {
                measurement_cb(NULL, poses[i].x, poses[i].y, poses[i].z, &device);
                g_assert_cmpint(orientation_calc(ORIENTATION_UNDEFINED,
                        captured.accel_x, captured.accel_y, captured.accel_z,
                        captured.scale), ==, poses[i].orientation);
        }
        for (int sign = -1; sign <= 1; sign += 2) {
                measurement_cb(NULL, 0, 0, sign * 9.81, &device);
                g_assert_cmpint(tilt_calc(TILT_UNDEFINED, captured.accel_x,
                        captured.accel_y, captured.accel_z, captured.scale), ==,
                        sign > 0 ? FACE_UP : FACE_DOWN);
        }
        g_print("SSC: four directions, tilted upright and both face orientations pass\n");
        return 0;
}
