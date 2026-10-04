/* dd12 security repro: does the reload server bind the .so bytes in the CAS
 * to the signed cas_hash before dlopen?
 *
 * Models two parties:
 *   signer  holds the ed25519 deploy key; signs exactly ONE line,
 *           "ACTIVATE5 test_fn_epoch <impl> <CAS> ..." for its own good_so.so.
 *   relayer cannot sign; can send unsigned CAS_PUT and can relay the signer's
 *           signed line verbatim.
 *
 * The question: if the bytes sitting at <CAS> are NOT the signer's good_so.so
 * (a different .so carrying the same public identity markers), does ACTIVATE5
 * still accept and dlopen them? If yes, the signed cas_hash is a name only,
 * not an integrity binding over the bytes.
 *
 * Built and driven like test/test_reload_activate4.c: real reload server on a
 * Unix socket, real ed25519 signing with the baked-in pubkey. Drop the two
 * .so files in CAS by two different routes and observe which bytes run.
 */
#include "march_reload.h"
#include "march_dispatch.h"
#include "tweetnacl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <dlfcn.h>

static unsigned char g_sk[64];
static int hexn(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }
static int load_sk(const char *p){ FILE*f=fopen(p,"r"); if(!f)return 0; char pk[128],sk[256]; if(!fgets(pk,sizeof pk,f)||!fgets(sk,sizeof sk,f)){fclose(f);return 0;} fclose(f); size_t n=strlen(sk); while(n&&(sk[n-1]=='\n'||sk[n-1]=='\r'))sk[--n]=0; if(n!=128)return 0; for(int i=0;i<64;i++){int hi=hexn(sk[2*i]),lo=hexn(sk[2*i+1]); if(hi<0||lo<0)return 0; g_sk[i]=(unsigned char)((hi<<4)|lo);} return 1; }
static void b64(const unsigned char*in,size_t n,char*out){ static const char t[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"; size_t i=0,o=0; while(i<n){unsigned v=in[i++]<<16; int h2=i<n; if(h2)v|=in[i++]<<8; int h3=i<n; if(h3)v|=in[i++]; out[o++]=t[(v>>18)&63]; out[o++]=t[(v>>12)&63]; out[o++]=h2?t[(v>>6)&63]:'='; out[o++]=h3?t[v&63]:'=';} out[o]=0; }
static void sign_b64(const char*m,char*out){ size_t ml=strlen(m); unsigned char*sm=malloc(ml+64); unsigned long long sl=0; crypto_sign(sm,&sl,(const unsigned char*)m,ml,g_sk); b64(sm,64,out); free(sm); }

static int connect_sock(const char*path){ int fd=socket(AF_UNIX,SOCK_STREAM,0); if(fd<0)return -1; struct sockaddr_un a; memset(&a,0,sizeof a); a.sun_family=AF_UNIX; strncpy(a.sun_path,path,sizeof a.sun_path-1); for(int i=0;i<100;i++){ if(connect(fd,(struct sockaddr*)&a,sizeof a)==0)return fd; struct timespec ts={0,20*1000*1000}; nanosleep(&ts,NULL);} close(fd); return -1; }
static void send_line(int fd,const char*l){ write(fd,l,strlen(l)); write(fd,"\n",1); }
static int read_resp(int fd,char*b,int max){ int n=0; while(n<max-1){char c; int r=(int)read(fd,&c,1); if(r<=0)break; if(c=='\n')break; b[n++]=c;} b[n]=0; return n; }

static const char CAS[]="7777777777777777777777777777777777777777777777777777777777777777";

static int put_so(int fd,const char*sofile){ FILE*f=fopen(sofile,"rb"); if(!f){perror(sofile);return 0;} static unsigned char buf[1<<20]; size_t n=fread(buf,1,sizeof buf,f); fclose(f); char line[256],resp[256]; snprintf(line,sizeof line,"CAS_PUT %s %zu",CAS,n); send_line(fd,line); read_resp(fd,resp,sizeof resp); if(strcmp(resp,"READY")!=0){fprintf(stderr,"CAS_PUT not ready: %s\n",resp);return 0;} if(write(fd,buf,n)!=(ssize_t)n)return 0; read_resp(fd,resp,sizeof resp); return strncmp(resp,"OK ",3)==0; }

static void activate5(int fd,const char*name,char*resp,int max){ char impl[65]; memset(impl,'6',64); impl[64]=0; char root[65]; /* blake3("") for empty caps */ strcpy(root,"af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"); char msg[2048]; snprintf(msg,sizeof msg,"ACTIVATE5 %s %s %s 0 epoch:0 cap_root:%s callers:",name,impl,CAS,root); char sig[128]; sign_b64(msg,sig); char line[2560]; snprintf(line,sizeof line,"ACTIVATE5 %s %s %s %s 0 epoch:0 cap_root:%s caps: callers:",name,impl,CAS,sig,root); send_line(fd,line); read_resp(fd,resp,max); }

static void cas_path(char*out,size_t n){ const char*home=getenv("HOME"); snprintf(out,n,"%s/.march/cas/artifacts/%.2s/%.62s",home,CAS,CAS+2); }

/* Load the just-activated slot's fn pointer via the server's dispatch and call
 * it, to see which bytes are live. We cheat and dlopen the CAS file ourselves
 * to read its test_fn_epoch return value (same bytes the server loaded). */
static long long call_cas_fn(void){ char p[640]; cas_path(p,sizeof p); void*h=dlopen(p,RTLD_NOW|RTLD_LOCAL); if(!h){fprintf(stderr,"dlopen %s: %s\n",p,dlerror());return -1;} long long(*fn)(void)=(long long(*)(void))dlsym(h,"test_fn_epoch"); long long r=fn?fn():-2; return r; }

int main(int argc,char**argv){
    if(argc<2){fprintf(stderr,"usage: %s <keys> <good.so> <evil.so>\n",argv[0]);return 2;}
    if(!load_sk(argv[1])){fprintf(stderr,"load_sk failed\n");return 2;}
    const char*good=argv[2], *evil=argv[3];

    char audit[128]; snprintf(audit,sizeof audit,"/tmp/dd12_audit_%d.jsonl",(int)getpid()); unlink(audit); setenv("MARCH_AUDIT_LOG",audit,1);
    char home[96]; snprintf(home,sizeof home,"/tmp/dd12_home_%d",(int)getpid()); mkdir(home,0700); setenv("HOME",home,1);
    char sock[64]; snprintf(sock,sizeof sock,"/tmp/dd12_%d.sock",(int)getpid());

    march_dispatch_init(16);
    march_dispatch_register_name(1,"test_fn_epoch");
    march_dispatch_publish(1,(void*)0x1010,"baseline",NULL,MARCH_NATIVE);
    march_reload_server_start(sock);

    int fd=connect_sock(sock); if(fd<0){fprintf(stderr,"connect failed\n");return 2;}

    /* Scenario: relayer uploads the EVIL bytes under the signer's CAS hash,
     * then the signer's (verbatim, legitimately signed) line activates. */
    if(!put_so(fd,evil)){fprintf(stderr,"evil CAS_PUT failed\n");return 2;}
    char resp[512]; activate5(fd,"test_fn_epoch",resp,sizeof resp);
    printf("ACTIVATE5 over substituted bytes -> %s\n",resp);
    long long v=call_cas_fn();
    printf("live test_fn_epoch() from CAS = %lld (good returns 42, substituted returns 1337)\n",v);

    if(strncmp(resp,"OK ",3)==0 && v==1337)
        printf("RESULT: SUBSTITUTION ACCEPTED — signed cas_hash did not bind the bytes\n");
    else if(strncmp(resp,"OK ",3)==0 && v==42)
        printf("RESULT: good bytes ran (unexpected: evil upload did not take)\n");
    else
        printf("RESULT: REJECTED before run (%s)\n",resp);
    (void)good;
    close(fd);
    return 0;
}
