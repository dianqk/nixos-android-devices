/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Feed real protobuf attributes/events through the production decoders. */
#define report_received sensor_report_received
#include "libssc-sensor.c"
#undef report_received
#define report_received accelerometer_report_received
#include "libssc-sensor-accelerometer.c"
#undef report_received

static gboolean received;
static const float sample[] = {0.073f, 9.23f, 3.49f};

static void capture(SSCSensorAccelerometer *sensor, float x, float y, float z,
                    gpointer user_data)
{
        g_assert_cmpfloat(x, ==, sample[0]);
        g_assert_cmpfloat(y, ==, sample[1]);
        g_assert_cmpfloat(z, ==, sample[2]);
        received = TRUE;
}

static void check_placement(const float *placement, size_t count)
{
        SSCSensorAccelerometer *sensor = g_object_new(SSC_TYPE_SENSOR_ACCELEROMETER,
                SSC_SENSOR_UID_LOW, (guint64)1, SSC_SENSOR_UID_HIGH, (guint64)2, NULL);
        SscAttrValue values[12];
        SscAttrValue *pointers[12];
        for (size_t i = 0; i < count; i++) {
                ssc_attr_value__init(&values[i]);
                values[i].has_f = TRUE;
                values[i].f = placement[i];
                pointers[i] = &values[i];
        }
        SscAttrArrayValue array = SSC_ATTR_ARRAY_VALUE__INIT;
        array.n_v = count;
        array.v = pointers;
        SscAttr attr = SSC_ATTR__INIT;
        attr.id = 20;
        attr.value_array = &array;
        SscAttr *attrs[] = {&attr};
        SscAttrResponse response = SSC_ATTR_RESPONSE__INIT;
        response.n_attr = 1;
        response.attr = attrs;
        GArray *buf = g_array_sized_new(FALSE, FALSE, 1,
                ssc_attr_response__get_packed_size(&response));
        g_array_set_size(buf, ssc_attr_response__get_packed_size(&response));
        ssc_attr_response__pack(&response, (guint8 *)buf->data);
        ReportReceivedContext ctx = { .sensor = SSC_SENSOR(sensor) };
        sensor_report_received(NULL, SSC_MSG_RESPONSE_GET_ATTRIBUTES, 2, 1, buf, &ctx);
        float (*matrix)[3];
        g_object_get(sensor, SSC_SENSOR_MOUNT_MATRIX, &matrix, NULL);
        for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++)
                        g_assert_cmpfloat(matrix[r][c], ==, r == c ? 1.0 : 0.0);

        SscAccelerometerResponse event = SSC_ACCELEROMETER_RESPONSE__INIT;
        event.n_acceleration = 3;
        event.acceleration = (float *)sample;
        event.accuracy = 3;
        g_array_set_size(buf, ssc_accelerometer_response__get_packed_size(&event));
        ssc_accelerometer_response__pack(&event, (guint8 *)buf->data);
        received = FALSE;
        g_signal_connect(sensor, "measurement", G_CALLBACK(capture), NULL);
        accelerometer_report_received(NULL, SSC_MSG_REPORT_MEASUREMENT, 2, 1, buf, sensor);
        while (g_main_context_pending(NULL))
                g_main_context_iteration(NULL, FALSE);
        g_assert_true(received);
        g_array_unref(buf);
        g_object_unref(sensor);
}

int main(void)
{
        const float placement[][12] = {
                {0, 1, 0, 0, -1, 0, 0, 10, 0, 0, 1, -2.5},
                {0.1, 0.1, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
                {0},
        };
        for (guint i = 0; i < G_N_ELEMENTS(placement); i++)
                check_placement(placement[i], 12);
        check_placement(placement[2], 0);
        g_print("SSC: placement rotation, translation, fractional, zero and empty metadata preserve device samples\n");
        return 0;
}
