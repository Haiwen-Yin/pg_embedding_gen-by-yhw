/*
 * pg-embedding-gen-by-yhw - PostgreSQL Embedding Extension using Configurable Models
 * 
 * This extension generates text embeddings by calling an external Python proxy
 * that can connect to various embedding models (BGE-M3, OpenAI, etc.)
 * 
 * Usage: SELECT generate_embedding('text to embed');
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "postgres.h"

#include "fmgr.h"
#include "utils/array.h"
#include "catalog/pg_type.h"
#include "lib/stringinfo.h"
#include "utils/builtins.h"  /* For StringGetTextDatum */

/* Always include PG_MODULE_MAGIC for extension compatibility */
PG_MODULE_MAGIC;

/* Default Python proxy path - can be overridden during deployment */
#define DEFAULT_PYTHON_PROXY_PATH "/usr/local/pgsql/bin/pg_embedding_proxy.py"

/* Extension version */
#define EXTENSION_VERSION "0.1.0 (Configurable Models)"

/* Helper to build PostgreSQL array from float values */
static ArrayType* build_float_array(float *values, int dim) {
    return construct_array(
        (Datum *)values,  /* Cast pointer to Datum array */
        dim, 
        FLOAT8OID,       /* Float8 OID for double precision */
        sizeof(double), 
        true,            /* By-value storage */
        TYPALIGN_DOUBLE);/* Alignment requirement */
}

/*
 * generate_embedding - Generate embedding vector for text input
 * 
 * SQL interface: SELECT generate_embedding('text to embed');
 * Returns: FLOAT[] array of embedding values
 */
PG_FUNCTION_INFO_V1(generate_embedding);

Datum generate_embedding(PG_FUNCTION_ARGS) {
    text *input_text = PG_GETARG_TEXT_P(0);
    
    /* Convert PostgreSQL text to C string */
    int len = VARSIZE_ANY_EXHDR(input_text);
    char *c_str = palloc(len + 1);
    memcpy(c_str, ((char *)VARDATA_ANY(input_text)), len);
    c_str[len] = '\0';
    
    /* Build command: python3 /path/to/proxy.py "text" --config /path/to/config.yaml */
    char command[4096];
    int cmd_len = snprintf(command, sizeof(command) - 1,
                          "python3 '%s' %s", DEFAULT_PYTHON_PROXY_PATH, c_str);
    command[sizeof(command) - 1] = '\0';
    
    /* Execute command and capture output */
    FILE *pipe = popen(command, "r");
    if (!pipe) {
        ereport(ERROR, 
                (errmsg("Failed to execute embedding generation command"),
                 errdetail("Cannot create pipe")));
    }
    
    /* Read output into buffer - use larger buffer for full JSON array output */
    char result[32768];  /* Larger buffer for complete JSON array output */
    int bytes_read = fread(result, 1, sizeof(result) - 1, pipe);
    pclose(pipe);
    
    if (bytes_read <= 0) {
        ereport(WARNING, 
                (errmsg("Empty response from Python proxy")));
        
        /* Return default single-element array [0.0] */
        float default_embed = 0.0;
        ArrayType *arr_result = build_float_array(&default_embed, 1);
        
        pfree(c_str);
        PG_RETURN_ARRAYTYPE_P(arr_result);
    }
    
    result[bytes_read] = '\0';
    
    /* Simple validation - output should start with '[' */
    if (result[0] != '[') {
        ereport(WARNING, 
                (errmsg("Invalid response format from Python proxy")));
        
        float default_embed = 0.0;
        ArrayType *arr_result = build_float_array(&default_embed, 1);
        
        pfree(c_str);
        PG_RETURN_ARRAYTYPE_P(arr_result);
    }
    
    /* Parse JSON array to extract dimensions by counting commas */
    int dims = 0;
    
    /* Count commas + 1 = number of elements in array */
    for (int i = 0; i < bytes_read && result[i] != ']'; i++) {
        if (result[i] == ',') dims++;
    }
    dims++;  /* Add last element */
    
    if (dims > 2048) {
        ereport(ERROR, 
                (errmsg("Embedding dimensions too large: %d", dims)));
    }
    
    /* Allocate memory for embedding values */
    float *embed_values = palloc(dims * sizeof(float));
    int idx = 0;
    
    /* Parse each float value from JSON array using sscanf */
    char num_str[64];
    
    /* Find start of first number after '[' */
    int pos = 1;
    while (pos < bytes_read && result[pos] != '-' && !isdigit(result[pos])) {
        pos++;
    }
    
    /* Parse all numbers in the array */
    while (pos < bytes_read && idx < dims) {
        if (result[pos] == ']') break;
        
        /* Extract number string - handle negative numbers and scientific notation */
        int start_pos = pos;
        while ((isdigit(result[pos]) || result[pos] == '.' || 
                result[pos] == 'e' || result[pos] == 'E' || result[pos] == '+' || 
                result[pos] == '-' || result[pos] == ' ') && pos < bytes_read) {
            /* Don't include trailing spaces */
            if (result[pos] != ' ' || (pos + 1 >= bytes_read || result[pos+1] != ']')) {
                num_str[idx++] = result[pos];
            } else {
                break;
            }
            pos++;
        }
        
        /* Convert to float and store */
        if (idx > 0) {
            int end_pos = strlen(num_str);
            if (end_pos < 64) {
                num_str[end_pos] = '\0';
                embed_values[idx-1] = atof(num_str);
            }
        }
        
        /* Move to next number */
        pos++;
    }
    
    /* Build PostgreSQL array return value */
    ArrayType *arr_result = build_float_array(embed_values, dims);
    
    pfree(c_str);
    PG_RETURN_ARRAYTYPE_P(arr_result);
}

/*
 * extension_version - Query extension version information (simplified)
 */
PG_FUNCTION_INFO_V1(extension_version);

Datum extension_version(PG_FUNCTION_ARGS) {
    /* Return constant string as text datum using StringGetTextDatum */
    return StringGetTextDatum(EXTENSION_VERSION);
}

/*
 * initialize_extension - Extension initialization function (optional)
 */
void _PG_init(void) {
    ereport(LOG, 
            (errmsg("pg-embedding-gen-by-yhw extension loaded v%s", EXTENSION_VERSION)));
}
