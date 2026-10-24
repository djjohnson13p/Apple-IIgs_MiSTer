// Local host-only compatibility for the bounded native simulator build.
#pragma once
#include <ctime>
#include <cstring>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <process.h>
static inline tm* lab_gmtime_r(const time_t* value, tm* result) {
    tm* source=std::gmtime(value); if(source) *result=*source;
    return source ? result : nullptr;
}
static inline tm* lab_localtime_r(const time_t* value, tm* result) {
    tm* source=std::localtime(value); if(source) *result=*source;
    return source ? result : nullptr;
}
static inline int lab_mkstemps(char* name, int suffix) {
    const size_t length=std::strlen(name);
    if(suffix<0 || length<size_t(suffix)+6) { errno=EINVAL; return -1; }
    static unsigned state=unsigned(std::time(nullptr)) ^ unsigned(_getpid());
    const char alphabet[]="abcdefghijklmnopqrstuvwxyz0123456789";
    for(unsigned attempt=0;attempt<256;++attempt) {
        for(unsigned i=0;i<6;++i) {
            state=state*1664525u+1013904223u;
            name[length-size_t(suffix)-6+i]=alphabet[(state>>16)%36];
        }
        int fd=_open(name,_O_CREAT|_O_EXCL|_O_RDWR|_O_BINARY,_S_IREAD|_S_IWRITE);
        if(fd>=0 || errno!=EEXIST) return fd;
    }
    errno=EEXIST; return -1;
}
