// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_LIB_INVOCATION_MIRROR_H_
#define RUNTIME_LIB_INVOCATION_MIRROR_H_

#include "vm/allocation.h"

namespace dart {

class InvocationMirror : public AllStatic {
 public:
  // These enum correspond to the constants in invocation_mirror_patch.dart.
  // It is used to communicate the reason for statically thrown
  // NoSuchMethodErrors by the compiler.
  enum Kind {
    // Constants describing the invocation type.
    // kField cannot be generated by regular invocation mirrors.
    kMethod = 0,
    kGetter = 1,
    kSetter = 2,
    kField = 3,
    kLocalVar = 4,
    kKindShift = 0,
    kKindBits = 3,
    kKindMask = (1 << kKindBits) - 1
  };

  enum Level {
    // These values, except kDynamic and kSuper, are only used when throwing
    // NoSuchMethodError for compile-time resolution failures.
    kDynamic = 0,
    kSuper = 1,
    kStatic = 2,
    kConstructor = 3,
    kTopLevel = 4,
    kLevelShift = kKindBits,
    kLevelBits = 3,
    kLevelMask = (1 << kLevelBits) - 1
  };

  static int EncodeType(Level level, Kind kind) {
    return (level << kLevelShift) | kind;
  }

  static void DecodeType(int type, Level* level, Kind* kind) {
    *level = static_cast<Level>(type >> kLevelShift);
    *kind = static_cast<Kind>(type & kKindMask);
  }
};

}  // namespace dart

#endif  // RUNTIME_LIB_INVOCATION_MIRROR_H_