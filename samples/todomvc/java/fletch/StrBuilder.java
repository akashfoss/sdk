// Copyright (c) 2015, the Fletch project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

// Generated file. Do not edit.

package fletch;

import java.util.List;
public class StrBuilder extends Builder {
  public static int kSize = 8;
  public StrBuilder(BuilderSegment segment, int offset) {
    super(segment, offset);
  }

  public StrBuilder() {
    super();
  }

  public List<Short> initChars(int length) {
    ListBuilder builder = new ListBuilder();
    newList(builder, 0, length, 1);
    return new Uint8ListBuilder(builder);
  }
}
