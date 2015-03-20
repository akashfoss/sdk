// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fletchc.driver;

import 'dart:io' hide
    stderr,
    stdin,
    stdout;

import 'dart:io' as io;

import 'dart:async' show
    Completer,
    Future,
    Stream,
    StreamIterator,
    StreamSubscription,
    Zone,
    ZoneSpecification;

import 'dart:typed_data' show
    ByteData,
    Endianness,
    TypedData,
    Uint8List;

import 'dart:convert' show
    UTF8;

import '../compiler.dart' show
    FletchCompiler;

const COMPILER_CRASHED = 253;
const DART_VM_EXITCODE_COMPILE_TIME_ERROR = 254;
const DART_VM_EXITCODE_UNCAUGHT_EXCEPTION = 255;

const Endianness commandEndianness = Endianness.LITTLE_ENDIAN;

enum DriverCommand {
  Stdin,  // Data on stdin.
  Stdout,  // Data on stdout.
  Stderr,  // Data on stderr.
  Arguments,  // Command-line arguments.
  Signal,  // Unix process signal received.
  ExitCode,  // Set process exit code.

  DriverConnectionError,  // Error in connection.
}

class StreamBuffer {
  final Stream<List<int>> stream;

  final StreamSubscription<List<int>> subscription;

  final BytesBuilder builder = new BytesBuilder(copy: false);

  int requestedBytes = 0;

  Completer<Uint8List> completer;

  StreamBuffer(Stream<List<int>> stream)
      : this.stream = stream,
        this.subscription = stream.listen(null) {
    subscription
        ..onData(handleData)
        ..onError(handleError)
        ..onDone(handleDone);
  }

  void handleData(Uint8List data) {
    builder.add(data);
    if (completer != null) {
      completeIfPossible();
    }
  }

  void handleError(error, StackTrace stackTrace) {
    Zone.ROOT.print(stringifyError(error, stackTrace));
    exit(1);
  }

  void handleDone() {
    if (completer != null) {
      completeIfPossible();
    }
    List trailing = builder.takeBytes();
    if (trailing.length != 0) {
      var error =
          new StateError(
              "Stream closed with trailing bytes "
              "(requestedBytes = $requestedBytes): $trailing");
      if (completer != null) {
        completer.completeError(error);
        completer = null;
        requestedBytes = 0;
      } else {
        throw error;
      }
    }
  }

  void completeIfPossible() {
    if (requestedBytes > builder.length) return;
    // BytesBuilder always returns a Uint8List.
    Uint8List list = builder.takeBytes();
    Completer<Uint8List> currentCompleter = completer;
    int currentRequestedBytes = requestedBytes;
    completer = null;
    requestedBytes = 0;
    if (currentRequestedBytes != list.length) {
      builder.add(
          makeView(
              list, currentRequestedBytes,
              list.length - currentRequestedBytes));
    }
    var result = makeView(list, 0, currentRequestedBytes);
    currentCompleter.complete(result);
  }

  Future<Uint8List> read(int length) {
    if (completer != null) {
      throw "Previous read not complete";
    }
    completer = new Completer<Uint8List>();
    Future<Uint8List> future = completer.future;
    requestedBytes = length;
    completeIfPossible();
    return future;
  }

  Future<int> readUint32([Endianness endian = Endianness.BIG_ENDIAN]) {
    return read(4).then((Uint8List list) {
      return new ByteData.view(list.buffer, list.offsetInBytes)
          .getUint32(0, endian);
    });
  }

  Future<dynamic> readCommand() async {
    int length = await readUint32(commandEndianness);
    Uint8List data = await read(length + 1);
    ByteData view = new ByteData.view(data.buffer, data.offsetInBytes + 1);
    DriverCommand command = DriverCommand.values[data[0]];
    switch (command) {
      case DriverCommand.Arguments:
        return decodeArgumentsCommand(view);
      default:
        throw "Command not implemented yet: $command";
    }
  }

  List<String> decodeArgumentsCommand(ByteData view) {
    int offset = 0;
    int argc = view.getUint32(offset, commandEndianness);
    offset += 4;
    List<String> argv = <String>[];
    for (int i = 0; i < argc; i++) {
      int length = view.getUint32(offset, commandEndianness);
      offset += 4;
      argv.add(UTF8.decode(makeView(view, offset, length)));
      offset += length;
    }
    return argv;
  }
}

Uint8List makeView(TypedData list, int offset, int length) {
  return new Uint8List.view(list.buffer, list.offsetInBytes + offset, length);
}

Future main(List<String> arguments) async {
  File configFile = new File.fromUri(Uri.base.resolve(arguments.first));

  ServerSocket server =
      await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);
  int port = server.port;

  // Write the port number to a config file. This lets multiple command line
  // programs share this persistent driver process, which in turn eliminates
  // start up overhead.
  configFile.writeAsStringSync("$port");

  // Print the port number so the launching process knows where to connect, and
  // that the socket port is ready.
  print(port);

  var connectionIterator = new StreamIterator(server);

  try {
    while (await connectionIterator.moveNext()) {
      await handleClient(
          handleSocketErrors(connectionIterator.current, "controlSocket"));
    }
  } finally {
    // TODO(ahe): Do this in a SIGTERM handler.
    configFile.delete();
  }
}

Function makeErrorHandler(String info) {
  return (error, StackTrace stackTrace) {
    Zone.ROOT.print("Error on $info: ${stringifyError(error, stackTrace)}");
  };
}

Socket handleSocketErrors(Socket socket, String name) {
  String remotePort = "?";
  try {
    remotePort = "${socket.remotePort}";
  } catch (_) {
    // Ignored, socket.remotePort may fail if the socket was closed on the
    // other side.
  }
  String info = "$name ${socket.port} -> $remotePort";
  // TODO(ahe): Remove the following line when things get more stable.
  Zone.ROOT.print(info);
  socket.done.catchError(makeErrorHandler(info));
  return socket;
}

StreamSubscription handleSubscriptionErrors(
    StreamSubscription subscription,
    String name) {
  String info = "$name subscription";
  Zone.ROOT.print(info);
  return subscription
      ..onError(makeErrorHandler(info));
}

String stringifyError(error, StackTrace stackTrace) {
  String safeToString(object) {
    try {
      return '$object';
    } catch (e) {
      return Error.safeToString(object);
    }
  }
  StringBuffer buffer = new StringBuffer();
  buffer.writeln(safeToString(error));
  if (stackTrace != null) {
    buffer.writeln(safeToString(stackTrace));
  } else {
    buffer.writeln("No stack trace.");
  }
  return '$buffer';
}

Future handleClient(Socket controlSocket) async {
  // Start another server socket to set up sockets for stdin, stdout, and
  // stderr.
  ServerSocket server =
      await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);
  int port = server.port;

  writeNetworkUint32(controlSocket, port);

  StreamBuffer controlBuffer = new StreamBuffer(controlSocket);

  List<String> arguments = await controlBuffer.readCommand();

  var connectionIterator = new StreamIterator(server);
  await connectionIterator.moveNext();

  // Socket for stdin and stdout.
  Socket stdio = handleSocketErrors(connectionIterator.current, "stdio");
  await connectionIterator.moveNext();

  // Socket for stderr.
  Socket stderr = handleSocketErrors(connectionIterator.current, "stderr");

  // Now that we have the sockets, close the server.
  server.close();

  ZoneSpecification specification =
      new ZoneSpecification(print: (_1, _2, _3, String line) {
        stdio.write('$line\n');
      },
      handleUncaughtError: (_1, _2, _3, error, StackTrace stackTrace) {
        String message =
            "\n\nExiting due to uncaught error.\n"
            "${stringifyError(error, stackTrace)}";
        Zone.ROOT.print(message);
        stderr.write(message);
        exit(1);
      });

  int exitCode = await Zone.current.fork(specification: specification)
      .run(() => compile(arguments.skip(1).toList(), stdio, stderr));
  stdio.destroy();
  stderr.destroy();

  writeNetworkUint32(controlSocket, exitCode);

  await controlSocket.flush();
  controlSocket.close();
}

void writeNetworkUint32(Socket socket, int i) {
  Uint8List list = new Uint8List(4);
  ByteData view = new ByteData.view(list.buffer);
  view.setUint32(0, i);
  socket.add(list);
}

Future<int> compile(List<String> arguments, Socket stdio, Socket stderr) async {
  List<String> options = const bool.fromEnvironment("fletchc-verbose")
      ? <String>['--verbose'] : <String>[];
  FletchCompiler compiler =
      new FletchCompiler(
          options: options, script: arguments.single,
          // TODO(ahe): packageRoot should be an option.
          packageRoot: "package/");
  bool compilerCrashed = false;
  List commands = await compiler.run().catchError((e, trace) {
    compilerCrashed = true;
    // TODO(ahe): Remove this catchError block when this bug is fixed:
    // https://code.google.com/p/dart/issues/detail?id=22437.
    print(e);
    print(trace);
    return [];
  });
  if (compilerCrashed) {
    return COMPILER_CRASHED;
  }

  var server = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);

  List<String> vmOptions = <String>[
      '--port=${server.port}',
      '-Xvalidate-stack',
  ];

  var connectionIterator = new StreamIterator(server);

  if (compiler.verbose) {
    print("Running '${compiler.fletchVm.toFilePath()} ${vmOptions.join(" ")}'");
  }
  var vmProcess =
      await Process.start(compiler.fletchVm.toFilePath(), vmOptions);

  handleSubscriptionErrors(stdio.listen(vmProcess.stdin.add), "stdin");
  handleSubscriptionErrors(vmProcess.stdout.listen(stdio.add), "vm stdout");
  handleSubscriptionErrors(vmProcess.stderr.listen(stderr.add), "vm stderr");

  bool hasValue = await connectionIterator.moveNext();
  assert(hasValue);
  var vmSocket = handleSocketErrors(connectionIterator.current, "vmSocket");
  server.close();

  vmSocket.listen(null).cancel();
  commands.forEach((command) => command.addTo(vmSocket));
  vmSocket.close();

  exitCode = await vmProcess.exitCode;
  if (exitCode != 0) {
    print("Non-zero exit code from VM ($exitCode).");
  }
  return exitCode;
}
