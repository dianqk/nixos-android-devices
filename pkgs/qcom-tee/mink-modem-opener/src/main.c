// SPDX-License-Identifier: BSD-3-Clause
//
// mink-modem-opener: the IMinkModemOpener service of Qualcomm's HLOS Mink
// daemon (ssgtzd) without the rest of the daemon. Publishes QRTR service
// 5013 v1 instance 1 and lets the modem open QTEE services through it
// (CTunnelInvokeMgr, UID 124), as minkipc's MinkDaemon start_modem_opener_service().

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "MinkCom.h"
#include "MinkModemOpener.h"
#include "libqrtr.h"
#include "minkipc.h"
#include "object.h"
#include "trace.h"

#define MINK_IPCR_MODEM_SERVICE 5013
#define MINK_IPCR_MODEM_SERVICE_VERSION 1
#define MINK_IPCR_MODEM_SERVICE_INSTANCE 1

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [--client-uid UID] [--trace] [--transport-trace]\n"
		"  --client-uid UID   present UID instead of the process UID in the\n"
		"                     QTEE client credentials (needs root)\n"
		"  --trace            log every invoke on the objects handed to the\n"
		"                     modem and to QTEE, with results and releases\n"
		"  --transport-trace  enable MinkSocket's own trace (needs a writable\n"
		"                     /tmp; creates /tmp/minksocketFullLog)\n",
		argv0);
}

/* libqcomtee encodes getuid() in the client credentials. */
static int get_client_env(Object root, long client_uid, Object *client_env)
{
	int ret;

	if (client_uid < 0)
		return MinkCom_getClientEnvObject(root, client_env);

	if (setresuid((uid_t)client_uid, (uid_t)-1, (uid_t)-1)) {
		fprintf(stderr, "setresuid(%ld): %s\n", client_uid, strerror(errno));
		return Object_ERROR;
	}
	ret = MinkCom_getClientEnvObject(root, client_env);
	if (setresuid(0, (uid_t)-1, (uid_t)-1)) {
		fprintf(stderr, "restoring the real UID: %s\n", strerror(errno));
		exit(1);
	}
	return ret;
}

int main(int argc, char **argv)
{
	static const struct option options[] = {
		{ "client-uid", required_argument, NULL, 'u' },
		{ "trace", no_argument, NULL, 't' },
		{ "transport-trace", no_argument, NULL, 'T' },
		{ "help", no_argument, NULL, 'h' },
		{ NULL, 0, NULL, 0 },
	};
	long client_uid = -1;
	bool transport_trace = false;
	Object root = Object_NULL;
	Object client_env = Object_NULL;
	Object opener = Object_NULL;
	struct timeval tv = { 0 };
	MinkIPC *service;
	char *end;
	int ret;
	int fd;
	int c;

	setvbuf(stdout, NULL, _IOLBF, 0);

	while ((c = getopt_long(argc, argv, "h", options, NULL)) != -1) {
		switch (c) {
		case 'u':
			errno = 0;
			client_uid = strtol(optarg, &end, 10);
			if (errno || *end || client_uid < 0) {
				usage(argv[0]);
				return 2;
			}
			break;
		case 't':
			gTraceEnabled = true;
			break;
		case 'T':
			transport_trace = true;
			break;
		case 'h':
			usage(argv[0]);
			return 0;
		default:
			usage(argv[0]);
			return 2;
		}
	}

	/* MinkSocket reads this flag file when the service starts. */
	if (transport_trace) {
		int flag = open("/tmp/minksocketFullLog", O_WRONLY | O_CREAT | O_CLOEXEC, 0600);

		if (flag < 0) {
			fprintf(stderr, "/tmp/minksocketFullLog: %s\n", strerror(errno));
			return 1;
		}
		close(flag);
	}

	ret = MinkCom_getRootEnvObject(&root);
	if (ret || Object_isNull(root)) {
		fprintf(stderr, "MinkCom_getRootEnvObject failed: %d\n", ret);
		return 1;
	}

	printf("getting the QTEE client environment as uid %ld\n",
	       client_uid < 0 ? (long)getuid() : client_uid);
	ret = get_client_env(root, client_uid, &client_env);
	if (ret || Object_isNull(client_env)) {
		fprintf(stderr, "MinkCom_getClientEnvObject failed: %d\n", ret);
		return 1;
	}

	ret = MinkModemOpener_new(client_env, &opener);
	Object_ASSIGN_NULL(client_env);
	if (ret) {
		fprintf(stderr, "MinkModemOpener_new failed: %d\n", ret);
		return 1;
	}
	opener = Trace_wrap(opener, "opener");

	fd = qrtr_open(0);
	if (fd < 0) {
		fprintf(stderr, "qrtr_open failed: %s\n", strerror(errno));
		return 1;
	}

	/* Blocking receive, as in MinkDaemon. */
	if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv))) {
		fprintf(stderr, "SO_RCVTIMEO: %s\n", strerror(errno));
		return 1;
	}

	if (qrtr_publish(fd, MINK_IPCR_MODEM_SERVICE, MINK_IPCR_MODEM_SERVICE_VERSION,
			 MINK_IPCR_MODEM_SERVICE_INSTANCE)) {
		fprintf(stderr, "qrtr_publish failed: %s\n", strerror(errno));
		return 1;
	}

	service = MinkIPC_startServiceOnSocket_QRTR(fd, opener);
	Object_ASSIGN_NULL(opener);
	if (!service) {
		fprintf(stderr, "MinkIPC_startServiceOnSocket_QRTR failed\n");
		return 1;
	}

	printf("serving IMinkModemOpener on QRTR service %d v%d instance %d%s%s\n",
	       MINK_IPCR_MODEM_SERVICE, MINK_IPCR_MODEM_SERVICE_VERSION,
	       MINK_IPCR_MODEM_SERVICE_INSTANCE, gTraceEnabled ? ", invoke trace" : "",
	       transport_trace ? ", transport trace" : "");

	MinkIPC_join(service);
	MinkIPC_release(service);
	Object_ASSIGN_NULL(root);
	return 0;
}
