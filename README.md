# BoxBuilder

Arbitrary logic during layout.

## Example

```dart
import 'dart:math';
import 'package:box_builder/box_builder.dart';

class Parent extends StatelessWidget {
  const Parent({super.key});

  @override
  Widget build(BuildContext context) {
    return BoxBuilder(builder: (context, constraints, build, order) {
      final a = build(const SizedBox(height: 200, width: 100));
      final b = build(const SizedBox(height: 200, width: 100));

      a.layout(constraints);
      b.layout(constraints);

      b.offset = Offset(0, a.size.height);

      return Size(max(a.size.width, b.size.width), a.size.height + b.size.height);
    });
  }
}
```

Would place box b under box a.