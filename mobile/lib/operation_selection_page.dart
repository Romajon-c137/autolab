part of 'main.dart';

class _OperationSelectionPage extends StatelessWidget {
  const _OperationSelectionPage({required this.storage});

  final _AppStorage storage;

  void _openOperation(BuildContext context, _OperationCategory operation) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            _InspectionFormPage(storage: storage, operationCategory: operation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Категория операции')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _OperationCategory.values.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final operation = _OperationCategory.values[index];
                return _MenuButton(
                  title: operation.label,
                  onTap: () => _openOperation(context, operation),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
