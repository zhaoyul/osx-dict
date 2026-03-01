/*
 * DictService.h
 *
 * Pure-C interface for querying the macOS built-in DictionaryServices
 * framework (DCSCopyTextDefinition) and, optionally, a remote translation
 * API via libcurl-compatible POSIX sockets.
 *
 * Callers must free() the returned string when done.
 */

#ifndef DICT_SERVICE_H
#define DICT_SERVICE_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Look up `word` in the system dictionary (offline, instant).
 * Returns a newly malloc'd UTF-8 string with the definition,
 * or NULL if the word was not found.  Caller must free().
 */
char *ds_lookup(const char *word);

/*
 * Trim `text` to the first `max_words` whitespace-separated tokens.
 * Useful for passing a short snippet to ds_lookup rather than a whole
 * paragraph.  Returns a newly malloc'd string.  Caller must free().
 */
char *ds_first_words(const char *text, int max_words);

#ifdef __cplusplus
}
#endif

#endif /* DICT_SERVICE_H */
