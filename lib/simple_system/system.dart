// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library dart.system;

class _StringImpl implements String {
  // TODO(ajohnsen): Implement.
  bool get isEmpty {
    return true;
  }
}

/// This is a magic method recognized by the compiler, and references to it
/// will be substituted for the actual main method.
/// [arguments] is supposed to be a List<String> with command line arguments.
/// [isolateArgument] is an extra argument that can be passed via
/// [Isolate.spawnUri].
external invokeMain([arguments, isolateArgument]);

/// This is the main entry point for a Fletch program, and it takes care of
/// calling "main" and exiting the VM when "main" is done.
entry(int mainArity) {
  invokeMain();
  yield(true);
}

/// Exits the VM cleanly.
external yield(bool halt);
