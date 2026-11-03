#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv) {
    if(argc != 2 || strcmp(argv[1],"--agent-command") != 0) return 8;
    char input[16384]; if(!fgets(input,sizeof(input),stdin)) return 9;
    if(strstr(input,"\"action\":\"oversized\"")) { for(int i=0;i<70000;i++) fputc('x',stdout); return 0; }
    if(strstr(input,"\"action\":\"invalid\"")) { fputs("not json",stdout); return 0; }
    if(strstr(input,"\"action\":\"failure\"")) { fputs("{\"ok\":false,\"status\":\"agent_paused\"}\n",stdout); return 1; }
    if(strstr(input,"\"action\":\"timeout\"")) { sleep(10); return 0; }
    fputs("{\"ok\":true,\"status\":\"fixture_ok\",\"revision\":7,\"windows\":[],\"echo\":",stdout);
    fputs(input,stdout);fputs(",\"padding\":\"",stdout);
    for(int i=0;i<30000;i++) fputc('x',stdout);
    fputs("\"}\n",stdout);return 0;
}
