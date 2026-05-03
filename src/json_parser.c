/*
 * json_parser.c - Simple JSON parsing for MVP embedding extraction
 * 
 * Provides basic JSON array parsing functionality without external dependencies.
 */

#include "postgres.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    double values[1024]; /* BGE-M3 max dimensions = 1024 */
    int count;
} JsonArray;

/*
 * Parse a simple JSON array string into double values.
 * Format: "[0.1, -0.2, 0.3, ...]"
 */
int parse_json_array(const char *json_str, JsonArray *array) {
    const char *start = strchr(json_str, '[');
    if (!start) return 0;
    
    start++; /* skip '[' */
    array->count = 0;
    
    while (*start && array->count < 1024) {
        /* Skip whitespace and commas */
        while (*start == ' ' || *start == ',') start++;
        
        if (!*start || *start == ']') break;
        
        /* Parse double value using strtod */
        char *endptr;
        double val = strtod(start, &endptr);
        
        if (endptr != start) {
            array->values[array->count++] = val;
            start = endptr;
        } else {
            break; /* No valid number found */
        }
    }
    
    return array->count;
}

/*
 * Calculate cosine similarity between two parsed arrays.
 * Returns value in range [0.0, 1.0] (for normalized vectors) or [-1.0, 1.0].
 */
double calculate_cosine_similarity(const JsonArray *a, const JsonArray *b) {
    if (a->count == 0 || b->count == 0) return 0.0;
    
    /* Use minimum of both counts to avoid out-of-bounds */
    int common_count = a->count < b->count ? a->count : b->count;
    
    double dot_product = 0.0, norm_a = 0.0, norm_b = 0.0;
    
    for (int i = 0; i < common_count; i++) {
        dot_product += a->values[i] * b->values[i];
        norm_a += a->values[i] * a->values[i];
        norm_b += b->values[i] * b->values[i];
    }
    
    if (norm_a == 0.0 || norm_b == 0.0) return 0.0;
    
    return dot_product / (sqrt(norm_a) * sqrt(norm_b));
}
