// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fletchc.driver.developer;

import 'dart:async' show
    Future;

import 'dart:io' show
    Socket,
    SocketException;

import 'session_manager.dart' show
    FletchVm,
    SessionState;

import 'driver_commands.dart' show
    handleSocketErrors;

import '../../commands.dart' show
    Debugging;

import '../verbs/infrastructure.dart' show
    DiagnosticKind,
    FletchDelta,
    IncrementalCompiler,
    Session,
    throwFatalError;

import '../../incremental/fletchc_incremental.dart' show
    IncrementalCompilationFailed;

import 'exit_codes.dart' show
    COMPILER_EXITCODE_CRASH;

Future<Null> attachToLocalVm(String programName, SessionState state) async {
  state.fletchVm = await FletchVm.start("$programName-vm");
  await attachToVm(state.fletchVm.host, state.fletchVm.port, state);
}

Future<Null> attachToVm(
    String host,
    int port,
    SessionState sessionState) async {
  Socket socket = await Socket.connect(host, port).catchError(
      (SocketException error) {
        String message = error.message;
        if (error.osError != null) {
          message = error.osError.message;
        }
        throwFatalError(
            DiagnosticKind.socketConnectError,
            address: '$host:$port', message: message);
      }, test: (e) => e is SocketException);
  String remotePort = "?";
  try {
    remotePort = "${socket.remotePort}";
  } catch (_) {
    // Ignored, socket.remotePort may fail if the socket was closed on the
    // other side.
  }

  Session session =
      new Session(handleSocketErrors(socket, "vmSocket"),
                  sessionState.compiler,
                  sessionState.stdoutSink,
                  sessionState.stderrSink,
                  null);

  // Enable debugging as a form of handshake.
  await session.runCommand(const Debugging());

  print("Connected to Fletch VM on TCP socket ${socket.port} -> $remotePort");

  sessionState.session = session;
}

Uri resolveUserInputFile(String script) {
  // TODO(ahe): Get base from current directory of C++ client. Also, this
  // method should probably be moved to infrastructure.dart or something.
  return Uri.base.resolve(script);
}

Future<int> compile(String script, SessionState state) async {
  Uri firstScript = state.script;
  List<FletchDelta> previousResults = state.compilationResults;
  Uri newScript = resolveUserInputFile(script);

  IncrementalCompiler compiler = state.compiler;

  FletchDelta newResult;
  try {
    if (previousResults.isEmpty) {
      state.script = newScript;
      await compiler.compile(newScript);
      newResult = compiler.computeInitialDelta();
    } else {
      try {
        print("Compiling difference from $firstScript to $newScript");
        newResult = await compiler.compileUpdates(
            previousResults.last.system, <Uri, Uri>{firstScript: newScript},
            logTime: print, logVerbose: print);
      } on IncrementalCompilationFailed catch (error) {
        print(error);
        print("Attempting full compile...");
        state.resetCompiler();
        state.script = newScript;
        await compiler.compile(newScript);
        newResult = compiler.computeInitialDelta();
      }
    }
  } catch (error, stackTrace) {
    // Don't let a compiler crash bring down the session.
    print(error);
    if (stackTrace != null) {
      print(stackTrace);
    }
    return COMPILER_EXITCODE_CRASH;
  }
  state.addCompilationResult(newResult);

  print("Compiled '$script' to ${newResult.commands.length} commands\n\n\n");

  return 0;
}