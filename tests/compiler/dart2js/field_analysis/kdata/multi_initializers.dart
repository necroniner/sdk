// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

main() {
  new Class1.a();
  new Class1.b();
}

class Class1 {
  /*element: Class1.field1:
    Class1.a=IntConstant(1),
    initial=IntConstant(0)
   */
  var field1 = 0;

  /*element: Class1.field2:
   Class1.a=IntConstant(1),
   Class1.b=IntConstant(2),
   initial=NullConstant
  */
  var field2;

  /*element: Class1.field3:
   Class1.a=IntConstant(3),
   Class1.b=IntConstant(3),
   initial=NullConstant
  */
  var field3;

  /*element: Class1.field4:initial=IntConstant(4)*/
  var field4 = 4;

  /*element: Class1.field5:
   Class1.a=IntConstant(5),
   Class1.b=IntConstant(5),
   initial=IntConstant(5)
  */
  var field5 = 5;

  Class1.a()
      : field1 = 1,
        field2 = 1,
        field3 = 3,
        field5 = 5;

  Class1.b()
      : field2 = 2,
        field3 = 3,
        field5 = 5;
}
