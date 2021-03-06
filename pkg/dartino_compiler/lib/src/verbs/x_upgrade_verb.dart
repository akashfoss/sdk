// Copyright (c) 2015, the Dartino project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library dartino_compiler.verbs.x_upgrade_verb;

import 'infrastructure.dart';
import '../worker/developer.dart' show upgradeAgent;
import 'documentation.dart' show upgradeDocumentation;

const Action upgradeAction = const Action(
    upgradeFunction,
    upgradeDocumentation,
    requiresSession: true,
    supportsWithUri: true,
    requiredTarget: TargetKind.AGENT);

Future upgradeFunction(AnalyzedSentence sentence, VerbContext context) async {
  return context.performTaskInWorker(
      new UpgradeTask(sentence.base, sentence.withUri));
}

class UpgradeTask extends SharedTask {
  final Uri base;
  final Uri package;

  UpgradeTask(this.base, this.package);

  Future call(
      CommandSender commandSender,
      StreamIterator<ClientCommand> commandIterator) async {
        return await upgradeAgent(commandSender, commandIterator,
            SessionState.current, base, package);
  }
}
