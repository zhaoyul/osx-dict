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
typedef CFArrayRef  (*DCSCopyAvailableDictionariesFn)(void);
typedef CFStringRef (*DCSGetShortNameFn)(void *dictionary);

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

static DCSCopyAvailableDictionariesFn load_dcs_available_dicts(void) {
    static DCSCopyAvailableDictionariesFn fn = NULL;
    static int loaded = 0;
    if (loaded) return fn;
    loaded = 1;

    void *handle = dlopen(DICT_SERVICES_PRIMARY_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle)
        handle = dlopen(DICT_SERVICES_FALLBACK_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return NULL;

    fn = (DCSCopyAvailableDictionariesFn)dlsym(handle, "DCSCopyAvailableDictionaries");
    return fn;
}

static DCSGetShortNameFn load_dcs_get_short_name(void) {
    static DCSGetShortNameFn fn = NULL;
    static int loaded = 0;
    if (loaded) return fn;
    loaded = 1;

    void *handle = dlopen(DICT_SERVICES_PRIMARY_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle)
        handle = dlopen(DICT_SERVICES_FALLBACK_PATH, RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return NULL;

    fn = (DCSGetShortNameFn)dlsym(handle, "DCSGetShortName");
    return fn;
}

/* ---------------------------------------------------------------------- */
/* Public API                                                               */
/* ---------------------------------------------------------------------- */

static char g_dictionary_name[256] = {0};

void ds_set_dictionary_name(const char *name) {
    if (!name || *name == '\0') {
        g_dictionary_name[0] = '\0';
        return;
    }
    snprintf(g_dictionary_name, sizeof(g_dictionary_name), "%s", name);
    g_dictionary_name[sizeof(g_dictionary_name) - 1] = '\0';
}

char *ds_lookup(const char *word) {
    if (!word || *word == '\0') return NULL;

    DCSCopyTextDefinitionFn DCSCopyTextDefinition = load_dcs();
    if (!DCSCopyTextDefinition) return NULL;

    CFStringRef cfWord = CFStringCreateWithCString(NULL, word,
                                                    kCFStringEncodingUTF8);
    if (!cfWord) return NULL;

    CFRange range = CFRangeMake(0, CFStringGetLength(cfWord));
    CFStringRef dictName = NULL;
    CFArrayRef dicts = NULL;
    void *dictArg = NULL;
    if (g_dictionary_name[0] != '\0') {
        dictName = CFStringCreateWithCString(NULL, g_dictionary_name,
                                             kCFStringEncodingUTF8);
        if (dictName) {
            DCSCopyAvailableDictionariesFn DCSCopyAvailableDictionaries =
                load_dcs_available_dicts();
            DCSGetShortNameFn DCSGetShortName = load_dcs_get_short_name();
            if (DCSCopyAvailableDictionaries && DCSGetShortName) {
                dicts = DCSCopyAvailableDictionaries();
                if (dicts) {
                    CFIndex n = CFArrayGetCount(dicts);
                    for (CFIndex i = 0; i < n; ++i) {
                        void *dict = (void *)CFArrayGetValueAtIndex(dicts, i);
                        if (!dict) continue;
                        CFStringRef shortName = DCSGetShortName(dict);
                        if (shortName &&
                            CFStringCompare(shortName, dictName, 0) == kCFCompareEqualTo) {
                            dictArg = dict;
                            break;
                        }
                    }
                }
            }
        }
    }
    CFStringRef definition = DCSCopyTextDefinition(dictArg, cfWord, range);
    CFRelease(cfWord);
    if (dicts) CFRelease(dicts);
    if (dictName) CFRelease(dictName);

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

char **ds_copy_dictionary_names(int *out_count) {
    if (out_count) *out_count = 0;

    DCSCopyAvailableDictionariesFn DCSCopyAvailableDictionaries =
        load_dcs_available_dicts();
    DCSGetShortNameFn DCSGetShortName = load_dcs_get_short_name();
    if (!DCSCopyAvailableDictionaries || !DCSGetShortName) return NULL;

    CFArrayRef dicts = DCSCopyAvailableDictionaries();
    if (!dicts) return NULL;

    CFIndex n = CFArrayGetCount(dicts);
    if (n <= 0) {
        CFRelease(dicts);
        return NULL;
    }

    char **names = calloc((size_t)n, sizeof(char *));
    if (!names) {
        CFRelease(dicts);
        return NULL;
    }

    int count = 0;
    for (CFIndex i = 0; i < n; ++i) {
        void *dict = (void *)CFArrayGetValueAtIndex(dicts, i);
        if (!dict) continue;
        CFStringRef shortName = DCSGetShortName(dict);
        if (!shortName) continue;
        CFIndex len = CFStringGetLength(shortName);
        CFIndex bufSize = CFStringGetMaximumSizeForEncoding(
                              len, kCFStringEncodingUTF8) + 1;
        char *cstr = malloc((size_t)bufSize);
        if (!cstr) continue;
        if (!CFStringGetCString(shortName, cstr, bufSize,
                                kCFStringEncodingUTF8)) {
            free(cstr);
            continue;
        }
        names[count++] = cstr;
    }
    CFRelease(dicts);

    if (count == 0) {
        free(names);
        return NULL;
    }
    if (out_count) *out_count = count;
    return names;
}

void ds_free_dictionary_names(char **names, int count) {
    if (!names) return;
    for (int i = 0; i < count; ++i) {
        free(names[i]);
    }
    free(names);
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
