#ifndef NFB_METHOD_LOOKUP_H
#define NFB_METHOD_LOOKUP_H

#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static inline BOOL NFBMethodTypeMatches(const char* actual, const char* expected) {
    if (actual == NULL || expected == NULL) return NO;
    while (*actual != '\0' && strchr("rnNoORV", *actual) != NULL) actual++;
    // Named object encodings still have the object-pointer ABI. Blocks use the
    // distinct @? encoding when a caller explicitly requires a block argument.
    if (strcmp(expected, "@") == 0) return actual[0] == '@' && actual[1] != '?';
    return strcmp(actual, expected) == 0;
}

// Validate new private hooks before installing their C IMPs. In particular,
// CGPoint and CGFloat arguments must use the expected arm64 ABI.
static inline BOOL NFBMethodHasSignature(Method method, const char* returnType,
                                         unsigned int count,
                                         const char* const* argumentTypes) {
    if (method == NULL || argumentTypes == NULL ||
        method_getNumberOfArguments(method) != count) return NO;
    char* actual = method_copyReturnType(method);
    BOOL matches = NFBMethodTypeMatches(actual, returnType);
    free(actual);
    if (!matches) return NO;
    for (unsigned int index = 0; index < count; index++) {
        actual = method_copyArgumentType(method, index);
        matches = NFBMethodTypeMatches(actual, argumentTypes[index]);
        free(actual);
        if (!matches) return NO;
    }
    return YES;
}

// Inspect method lists only. class_getInstanceMethod may call a method resolver
// for a missing selector; doing that on an unregistered metaclass can abort.
static inline Method NFBFindMethodWithoutResolving(Class cls, SEL selector) {
    if (selector == NULL) return NULL;
    for (Class cursor = cls; cursor != Nil; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method* methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (sel_isEqual(method_getName(methods[index]), selector)) {
                found = methods[index];
                break;
            }
        }
        free(methods);
        if (found != NULL) return found;
    }
    return NULL;
}

// Read encodings from the registered parent, never from the class under
// construction. Metadata inspection must not message either class.
static inline BOOL NFBAddInheritedOverride(Class subclass, Class parent,
                                           BOOL isClassMethod, SEL selector,
                                           IMP implementation) {
    if (subclass == Nil || parent == Nil) return NO;
    Class source = isClassMethod ? object_getClass(parent) : parent;
    Class destination = isClassMethod ? object_getClass(subclass) : subclass;
    Method inherited = NFBFindMethodWithoutResolving(source, selector);
    return inherited != NULL && class_addMethod(destination, selector,
        implementation, method_getTypeEncoding(inherited));
}

#endif
