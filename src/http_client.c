/*
 * http_client.c - HTTP client module for embedding API calls
 * 
 * Provides robust HTTP POST functionality for calling embedding APIs.
 */

#include "postgres.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *response;
    int status_code;
} HttpResponse;

/*
 * Make HTTP POST request using curl via popen (MVP approach)
 * Returns response body as dynamically allocated string.
 */
char* http_post(const char *url, const char *content_type, const char *payload) {
    char cmd[1024];
    
    snprintf(cmd, sizeof(cmd),
             "curl -s -w '%%{http_code}' -X POST '%s' "
             "-H 'Content-Type: %s' -d '%s'",
             url, content_type, payload);
    
    FILE *fp = popen(cmd, "r");
    if (!fp) return NULL;
    
    /* Read full response (HTTP code + body) */
    char buffer[8192];
    size_t total_read = fread(buffer, 1, sizeof(buffer)-1, fp);
    buffer[total_read] = '\0';
    
    pclose(fp);
    
    /* For MVP: return raw response string */
    char *result = strdup(buffer);
    return result;
}

/* Helper to extract HTTP status code from curl output */
int get_http_status(const char *response) {
    const char *last_space = strrchr(response, ' ');
    if (last_space && strlen(last_space) <= 4) {
        /* Last 3 chars are likely the status code */
        return atoi(last_space + 1);
    }
    return 0;
}
