#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <evntrace.h>
#include <evntcons.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
static FILE *out;
static unsigned long long count;
static const GUID thread_provider={0x3d6fa8d1,0xfe05,0x11d0,{0x9d,0xda,0x00,0xc0,0x4f,0xd7,0xba,0x7c}};
static void WINAPI record(EVENT_RECORD *event) {
    if (memcmp(&event->EventHeader.ProviderId,&thread_provider,sizeof(GUID)) || event->EventHeader.EventDescriptor.Opcode!=36) return;
    fprintf(out,"%lld,%u,%lu,%lu,%u,",event->EventHeader.TimeStamp.QuadPart,(unsigned)event->BufferContext.ProcessorNumber,(unsigned long)event->EventHeader.ProcessId,(unsigned long)event->EventHeader.ThreadId,(unsigned)event->UserDataLength);
    for (unsigned i=0;i<event->UserDataLength;i++) fprintf(out,"%02x",((unsigned char*)event->UserData)[i]);
    fputc('\n',out);count++;
}
int wmain(int argc,wchar_t **argv) {
    if(argc!=3) return 2;
    out=_wfopen(argv[2],L"wb");if(!out)return 3;
    EVENT_TRACE_LOGFILEW logfile={0};logfile.LogFileName=argv[1];
    logfile.ProcessTraceMode=PROCESS_TRACE_MODE_EVENT_RECORD|PROCESS_TRACE_MODE_RAW_TIMESTAMP;
    logfile.EventRecordCallback=record;
    TRACEHANDLE handle=OpenTraceW(&logfile);
    if(handle==INVALID_PROCESSTRACE_HANDLE){fprintf(stderr,"OpenTrace=%lu\n",GetLastError());fclose(out);return 4;}
    fprintf(out,"frequency,%lld\n",logfile.LogfileHeader.PerfFreq.QuadPart);
    fprintf(out,"clock_type,%lu\n",logfile.LogfileHeader.ReservedFlags);
    fprintf(out,"qpc,cpu,header_pid,header_tid,payload_length,payload_hex\n");
    ULONG result=ProcessTrace(&handle,1,NULL,NULL);ULONG close_result=CloseTrace(handle);
    int failed=ferror(out);fclose(out);
    fprintf(stderr,"ProcessTrace=%lu CloseTrace=%lu CSwitch=%llu WriteError=%d\n",result,close_result,count,failed);
    return result||close_result||failed?5:0;
}
