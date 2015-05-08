// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

#include "src/vm/ffi.h"

#include <dlfcn.h>
#include <errno.h>

#include "src/vm/natives.h"
#include "src/vm/object.h"
#include "src/vm/port.h"
#include "src/vm/process.h"

namespace fletch {

class DefaultLibraryEntry {
 public:
  DefaultLibraryEntry(char* library, DefaultLibraryEntry* next)
      : library_(library), next_(next) {
  }

  ~DefaultLibraryEntry() {
    free(library_);
  }

  const char* library() const { return library_; }
  DefaultLibraryEntry* next() const { return next_; }

 private:
  char* library_;
  DefaultLibraryEntry* next_;
};

DefaultLibraryEntry* ForeignFunctionInterface::libraries_ = NULL;
Mutex* ForeignFunctionInterface::mutex_ = NULL;

void ForeignFunctionInterface::Setup() {
  mutex_ = Platform::CreateMutex();
}

void ForeignFunctionInterface::TearDown() {
  DefaultLibraryEntry* current = libraries_;
  while (current != NULL) {
    DefaultLibraryEntry* next = current->next();
    delete current;
    current = next;
  }
  delete mutex_;
}

void ForeignFunctionInterface::AddDefaultSharedLibrary(const char* library) {
  ScopedLock lock(mutex_);
  libraries_ = new DefaultLibraryEntry(strdup(library), libraries_);
}

static void* PerformForeignLookup(const char* library, const char* name) {
  void* handle = dlopen(library, RTLD_LOCAL | RTLD_LAZY);
  if (handle == NULL) return NULL;
  void* result = dlsym(handle, name);
  if (dlclose(handle) != 0) return NULL;
  return result;
}

void* ForeignFunctionInterface::LookupInDefaultLibraries(const char* symbol) {
  ScopedLock lock(mutex_);
  for (DefaultLibraryEntry* current = libraries_;
       current != NULL;
       current = current->next()) {
    void* result = PerformForeignLookup(current->library(), symbol);
    if (result != NULL) return result;
  }
  return NULL;
}

NATIVE(ForeignLookup) {
  char* library = arguments[1]->IsString()
      ? AsForeignString(String::cast(arguments[1]))
      : NULL;

  char* name = AsForeignString(String::cast(arguments[0]));
  void* result = PerformForeignLookup(library, name);

  if (result == NULL) {
    result = ForeignFunctionInterface::LookupInDefaultLibraries(name);
  }

  if (result == NULL) fprintf(stderr, "Failed foreign lookup: %s\n", name);

  free(library);
  free(name);

  return result != NULL
      ? process->ToInteger(reinterpret_cast<intptr_t>(result))
      : Failure::index_out_of_bounds();
}

NATIVE(ForeignAllocate) {
  word size = AsForeignWord(arguments[0]);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  void* calloc_value = calloc(1, size);
  uint64 value = reinterpret_cast<uint64>(calloc_value);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignFree) {
  word address = AsForeignWord(arguments[0]);
  free(reinterpret_cast<void*>(address));
  return process->program()->null_object();
}

NATIVE(ForeignMarkForFinalization) {
  HeapObject* foreign = HeapObject::cast(arguments[0]);
  process->RegisterFinalizer(foreign, Process::FinalizeForeign);
  return process->program()->null_object();
}

NATIVE(ForeignBitsPerWord) {
  return Smi::FromWord(kBitsPerWord);
}

NATIVE(ForeignErrno) {
  return Smi::FromWord(errno);
}

NATIVE(ForeignPlatform) {
  return Smi::FromWord(Platform::OS());
}

NATIVE(ForeignArchitecture) {
  return Smi::FromWord(Platform::Arch());
}

NATIVE(ForeignConvertPort) {
  if (!arguments[0]->IsInstance()) return Smi::zero();
  Instance* instance = Instance::cast(arguments[0]);
  if (!instance->IsPort()) return Smi::zero();
  Object* field = instance->GetInstanceField(0);
  uword address = AsForeignWord(field);
  if (address == 0) return Smi::zero();
  Port* port = reinterpret_cast<Port*>(address);
  Object* result = process->ToInteger(reinterpret_cast<intptr_t>(port));
  if (result == Failure::retry_after_gc()) return result;
  port->IncrementRef();
  return result;
}

typedef int (*F0)();
typedef int (*F1)(word);
typedef int (*F2)(word, word);
typedef int (*F3)(word, word, word);
typedef int (*F4)(word, word, word, word);
typedef int (*F5)(word, word, word, word, word);
typedef int (*F6)(word, word, word, word, word, word);

NATIVE(ForeignICall0) {
  word address = AsForeignWord(arguments[0]);
  F0 function = reinterpret_cast<F0>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function();
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall1) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  F1 function = reinterpret_cast<F1>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall2) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  F2 function = reinterpret_cast<F2>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0, a1);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall3) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  F3 function = reinterpret_cast<F3>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0, a1, a2);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall4) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  F4 function = reinterpret_cast<F4>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0, a1, a2, a3);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall5) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  word a4 = AsForeignWord(arguments[5]);
  F5 function = reinterpret_cast<F5>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0, a1, a2, a3, a4);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

NATIVE(ForeignICall6) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  word a4 = AsForeignWord(arguments[5]);
  word a5 = AsForeignWord(arguments[6]);
  F6 function = reinterpret_cast<F6>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int value = function(a0, a1, a2, a3, a4, a5);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

typedef void (*VF0)();
typedef void (*VF1)(word);
typedef void (*VF2)(word, word);
typedef void (*VF3)(word, word, word);
typedef void (*VF4)(word, word, word, word);
typedef void (*VF5)(word, word, word, word, word);
typedef void (*VF6)(word, word, word, word, word, word);

NATIVE(ForeignVCall0) {
  word address = AsForeignWord(arguments[0]);
  VF0 function = reinterpret_cast<VF0>(address);
  function();
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall1) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  VF1 function = reinterpret_cast<VF1>(address);
  function(a0);
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall2) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  VF2 function = reinterpret_cast<VF2>(address);
  function(a0, a1);
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall3) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  VF3 function = reinterpret_cast<VF3>(address);
  function(a0, a1, a2);
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall4) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  VF4 function = reinterpret_cast<VF4>(address);
  function(a0, a1, a2, a3);
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall5) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  word a4 = AsForeignWord(arguments[5]);
  VF5 function = reinterpret_cast<VF5>(address);
  function(a0, a1, a2, a3, a4);
  return Smi::FromWord(0);
}

NATIVE(ForeignVCall6) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  word a1 = AsForeignWord(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  word a3 = AsForeignWord(arguments[4]);
  word a4 = AsForeignWord(arguments[5]);
  word a5 = AsForeignWord(arguments[6]);
  VF6 function = reinterpret_cast<VF6>(address);
  function(a0, a1, a2, a3, a4, a5);
  return Smi::FromWord(0);
}

typedef int64 (*LwLw)(word, int64, word);

static int64 AsInt64Value(Object* object) {
  if (object->IsSmi()) return Smi::cast(object)->value();
  if (object->IsLargeInteger()) return LargeInteger::cast(object)->value();
  UNREACHABLE();
  return -1;
}

NATIVE(ForeignLCallwLw) {
  word address = AsForeignWord(arguments[0]);
  word a0 = AsForeignWord(arguments[1]);
  int64 a1 = AsInt64Value(arguments[2]);
  word a2 = AsForeignWord(arguments[3]);
  LwLw function = reinterpret_cast<LwLw>(address);
  Object* result = process->NewInteger(0);
  if (result == Failure::retry_after_gc()) return result;
  int64 value = function(a0, a1, a2);
  if (Smi::IsValid(value)) {
    process->TryDeallocInteger(LargeInteger::cast(result));
    return Smi::FromWord(value);
  }
  LargeInteger::cast(result)->set_value(value);
  return result;
}

#define DEFINE_FOREIGN_ACCESSORS_INTEGER(suffix, type)                   \
                                                                         \
NATIVE(ForeignGet##suffix) {                                             \
  type* address = reinterpret_cast<type*>(AsForeignWord(arguments[0]));  \
  return process->ToInteger(*address);                                   \
}                                                                        \
                                                                         \
NATIVE(ForeignSet##suffix) {                                             \
  Object* value = arguments[1];                                          \
  if (!value->IsSmi() && !value->IsLargeInteger()) {                     \
    return Failure::wrong_argument_type();                               \
  }                                                                      \
  type* address = reinterpret_cast<type*>(AsForeignWord(arguments[0]));  \
  *address = AsForeignWord(value);                                       \
  return value;                                                          \
}

DEFINE_FOREIGN_ACCESSORS_INTEGER(Int8, int8)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Int16, int16)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Int32, int32)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Int64, int64)

DEFINE_FOREIGN_ACCESSORS_INTEGER(Uint8, uint8)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Uint16, uint16)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Uint32, uint32)
DEFINE_FOREIGN_ACCESSORS_INTEGER(Uint64, uint64)

#define DEFINE_FOREIGN_ACCESSORS_DOUBLE(suffix, type)                    \
                                                                         \
NATIVE(ForeignGet##suffix) {                                             \
  type* address = reinterpret_cast<type*>(AsForeignWord(arguments[0]));  \
  return process->NewDouble(static_cast<double>(*address));              \
}                                                                        \
                                                                         \
NATIVE(ForeignSet##suffix) {                                             \
  Object* value = arguments[1];                                          \
  if (!value->IsDouble()) return Failure::wrong_argument_type();         \
  type* address = reinterpret_cast<type*>(AsForeignWord(arguments[0]));  \
  *address = Double::cast(value)->value();                               \
  return value;                                                          \
}

DEFINE_FOREIGN_ACCESSORS_DOUBLE(Float32, float)
DEFINE_FOREIGN_ACCESSORS_DOUBLE(Float64, double)

#undef DEFINE_FOREIGN_ACCESSORS

}  // namespace fletch
