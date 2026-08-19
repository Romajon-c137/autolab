part of 'main.dart';

class _SignaturePage extends StatefulWidget {
  const _SignaturePage({required this.storage});

  final _AppStorage storage;

  @override
  State<_SignaturePage> createState() => _SignaturePageState();
}

class _SignaturePageState extends State<_SignaturePage> {
  late List<List<Offset>> _strokes;
  String? _status;

  @override
  void initState() {
    super.initState();
    _strokes = widget.storage.loadSignature();
  }

  void _startStroke(DragStartDetails details) {
    setState(() {
      _status = null;
      _strokes.add([details.localPosition]);
    });
  }

  void _appendPoint(DragUpdateDetails details) {
    if (_strokes.isEmpty) {
      return;
    }

    setState(() {
      _strokes.last.add(details.localPosition);
    });
  }

  Future<void> _save() async {
    await widget.storage.saveSignature(_strokes);
    if (!mounted) {
      return;
    }

    setState(() => _status = 'Подпись сохранена.');
  }

  Future<void> _clear() async {
    setState(() {
      _strokes = [];
      _status = null;
    });
    await widget.storage.saveSignature(_strokes);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Подпись')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.storage.userLabel ?? 'Пользователь',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _startStroke,
                      onPanUpdate: _appendPoint,
                      child: CustomPaint(
                        painter: _SignaturePainter(strokes: _strokes),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                _StatusBox(text: _status!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Очистить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) {
        continue;
      }

      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.6, paint);
        continue;
      }

      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return true;
  }
}
