#ifndef RUBY_FFI_H
#define RUBY_FFI_H 1

#ifdef HAVE_STDBOOL_H
# include <stdbool.h>
#else
typedef int bool;
# undef true
# define true 1
# undef false
# define false 0
#endif

typedef struct AbstractMemory_ {
  char *address;
  long size;
  int flags;
  int typeSize;
} AbstractMemory;

typedef struct Pointer {
  AbstractMemory memory;
  VALUE rbParent;
  char *storage;
  bool autorelease;
  bool allocated;
} Pointer;

#endif /* RUBY_FFI_H */
