# SPDX-License-Identifier: BSD-3-Clause
# Copied to the root of the minkipc source tree before the build.
project('mink-modem-opener', 'c', version : '0.1.0', default_options : ['warning_level=1'])

idlc = find_program('idlc')
qrtr = dependency('qrtr')
minkadaptor = dependency('minkadaptor')
threads = dependency('threads')

sdk_idl = 'libmink/SDK/QTVM/idl'
cbo_idl = 'listeners/listenercbo/idl'
idls = {
  'CTunnelInvokeMgr' : sdk_idl,
  'ICredentials' : sdk_idl,
  'IMinkModemOpener' : sdk_idl,
  'IModule' : sdk_idl,
  'IOpener' : sdk_idl,
  'ITAccessPermissions' : sdk_idl,
  'IClientEnv' : cbo_idl,
  'IIO' : cbo_idl,
  'IPrimordial' : 'mink-modem-opener',
}
headers = []
foreach name, dir : idls
  headers += custom_target(name + '.h', input : dir / name + '.idl', output : name + '.h',
    command : [idlc, '@INPUT@', '-o', '@OUTPUT@'])
  headers += custom_target(name + '_invoke.h', input : dir / name + '.idl',
    output : name + '_invoke.h', command : [idlc, '@INPUT@', '-o', '@OUTPUT@', '--skel'])
endforeach

ms = 'libmink/Transport/MinkSocket'
sources = files(
  ms / 'ext/itoa.c',
  ms / 'sock/CredentialsAdapter.c',
  ms / 'sock/LinkCredentials.c',
  ms / 'sock/Marshalling.c',
  ms / 'sock/ObjectTable.c',
  ms / 'sock/Primordial.c',
  ms / 'sock/Profiling.c',
  ms / 'sock/SockAgnostic.c',
  ms / 'sock/SockQRTR.c',
  ms / 'sock/ThreadPool.c',
  ms / 'sock/Utils.c',
  ms / 'sock/minkipc.c',
  ms / 'sock/minksocket.c',
  ms / 'sock/msforwarder.c',
  ms / 'sock/xtzdCredentials.c',
  ms / 'sharemm/src/MSMem.c',
  ms / 'vmosal/VmOsalUnix.c',
  'libmink/Transport/FdWrapper/src/fdwrapper.c',
  'mink-modem-opener/MinkModemOpener.c',
  'mink-modem-opener/main.c',
  'mink-modem-opener/sharemm_stubs.c',
  'mink-modem-opener/trace.c',
)

executable('mink-modem-opener', sources, headers,
  c_args : [
    '-D_GNU_SOURCE',
    '-DVNDR_SMCINVOKE_QRTR',
    '-include', meson.project_source_root() / 'mink-modem-opener/mink_compat.h',
    '-Wno-unused-parameter',
    '-Wno-missing-field-initializers',
  ],
  include_directories : include_directories(
    'mink-modem-opener',
    ms / 'include',
    ms / 'kernel',
    ms / 'sock',
    ms / 'sharemm/inc',
    'libmink/Transport/FdWrapper/interface',
  ),
  dependencies : [qrtr, minkadaptor, threads],
  install : true,
)
