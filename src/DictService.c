/*
 * DictService.c
 *
 * Wraps the private DictionaryServices framework that backs the macOS
 * "Look Up" feature (three-finger tap, Force Touch, etc.).
 *
 * The framework is private, so we load it dynamically to avoid a hard
 * link-time dependency.  The function signature has been stable since
 * OS X 10.5.
 */

#include "DictService.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <CoreFoundation/CoreFoundation.h>

/* ---------------------------------------------------------------------- */
/* Dynamic loading of DictionaryServices                                    */
/* ---------------------------------------------------------------------- */

typedef CFStringRef (*DCSCopyTextDefinitionFn)(void *dictionary,
                                               CFStringRef word,
                                               CFRange range);

/* Canonical path for DictionaryServices on macOS 10.6+ */
#define DICT_SERVICES_PRIMARY_PATH \
    "/System/Library/Frameworks/CoreServices.framework" \
    "/Versions/A/Frameworks/DictionaryServices.framework" \
    "/Versions/A/DictionaryServices"

/* Fallback path used on some older macOS versions */
#define DICT_SERVICES_FALLBACK_PATH \
    "/System/Library/PrivateFrameworks/DictionaryServices.framework" \
    "/DictionaryServices"

static DCSCopyTextDefinitionFn load_dcs(void) {
    static DCSCopyTextDefinitionFn fn = NULL;
    static int loaded = 0;
    if (loaded) return fn;
    loaded = 1;

    void *handle = dlopen(DICT_SERVICES_PRIMARY_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle)
        handle = dlopen(DICT_SERVICES_FALLBACK_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "osx-dict: cannot load DictionaryServices: %s\n",
                dlerror());
        return NULL;
    }

    fn = (DCSCopyTextDefinitionFn)dlsym(handle, "DCSCopyTextDefinition");
    if (!fn) {
        fprintf(stderr, "osx-dict: DCSCopyTextDefinition not found: %s\n",
                dlerror());
    }
    return fn;
}

/* ---------------------------------------------------------------------- */
/* Public API                                                               */
/* ---------------------------------------------------------------------- */

char *ds_lookup(const char *word) {
    if (!word || *word == '\0') return NULL;

    DCSCopyTextDefinitionFn DCSCopyTextDefinition = load_dcs();
    if (!DCSCopyTextDefinition) return NULL;

    CFStringRef cfWord = CFStringCreateWithCString(NULL, word,
                                                    kCFStringEncodingUTF8);
    if (!cfWord) return NULL;

    CFRange range = CFRangeMake(0, CFStringGetLength(cfWord));
    CFStringRef definition = DCSCopyTextDefinition(NULL, cfWord, range);
    CFRelease(cfWord);

    if (!definition) return NULL;

    /* Convert CFString → C string */
    CFIndex cfLen = CFStringGetLength(definition);
    CFIndex bufSize = CFStringGetMaximumSizeForEncoding(
                          cfLen, kCFStringEncodingUTF8) + 1;
    char *result = malloc((size_t)bufSize);
    if (result) {
        if (!CFStringGetCString(definition, result, bufSize,
                                kCFStringEncodingUTF8)) {
            free(result);
            result = NULL;
        }
    }
    CFRelease(definition);
    return result;
}

char *ds_first_words(const char *text, int max_words) {
    if (!text || max_words <= 0) return NULL;

    /* Work on a copy so we can modify it */
    char *copy = strdup(text);
    if (!copy) return NULL;

    int words = 0;
    char *p = copy;

    /* Skip leading whitespace */
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;

    char *start = p;

    while (*p) {
        /* Find end of current word */
        while (*p && *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r')
            p++;
        words++;
        if (words >= max_words) {
            *p = '\0'; /* truncate here */
            break;
        }
        /* Skip whitespace between words */
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r') p++;
    }

    char *result = strdup(start);
    free(copy);
    return result;
}
