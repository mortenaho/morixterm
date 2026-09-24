#ifndef WINPR_BUILD_FLAGS_H
#define WINPR_BUILD_FLAGS_H

#define WINPR_CFLAGS "-g -O2 -Werror=implicit-function-declaration -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -ffile-prefix-map=<src dir>=. -flto=auto -ffat-lto-objects -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -fdebug-prefix-map=<src dir>=/usr/src/freerdp3-3.31.0+dfsg-0ubuntu0.26.04.1 -Wdate-time -D_FORTIFY_SOURCE=3 -DNDEBUG -Wdate-time -D_FORTIFY_SOURCE=3 -fvisibility=hidden -fno-omit-frame-pointer -Wredundant-decls -fsigned-char -Wimplicit-function-declaration -Wno-jump-misses-init -fvisibility=hidden -O2 -g -DNDEBUG"
#define WINPR_COMPILER_ID "GNU"
#define WINPR_COMPILER_VERSION "15.2.0"
#define WINPR_TARGET_ARCH "x64"
#define WINPR_BUILD_CONFIG ""
#define WINPR_BUILD_TYPE "RelWithDebInfo"

#endif /* WINPR_BUILD_FLAGS_H */
