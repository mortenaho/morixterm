#include "SecurityHardening.h"
#include <QtGlobal>

#ifdef Q_OS_UNIX
#include <sys/resource.h>
#include <sys/stat.h>
#endif
#ifdef Q_OS_LINUX
#include <sys/prctl.h>
#endif
#ifdef Q_OS_WIN
#include <windows.h>
#endif

void SecurityHardening::apply()
{
#ifdef Q_OS_UNIX
    // Files created by MoriXterm are private to the current user unless explicitly changed.
    ::umask(0077);
    struct rlimit coreLimit {};
    coreLimit.rlim_cur = 0;
    coreLimit.rlim_max = 0;
    ::setrlimit(RLIMIT_CORE, &coreLimit);
#endif
#ifdef Q_OS_LINUX
    // PR_SET_DUMPABLE=0 blocks some GNOME/desktop portal integrations because they
    // legitimately inspect /proc/<pid>. Keep that extra-hardening mode opt-in.
    // Core dumps remain disabled above for every run.
    if (qEnvironmentVariableIntValue("MORIXTERM_STRICT_NO_DUMP") == 1)
        ::prctl(PR_SET_DUMPABLE, 0, 0, 0, 0);
#endif
#ifdef Q_OS_WIN
    ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
#endif
}
