import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:server_ping/main.dart';

void main() {
  testWidgets('shows login form', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AutoInspectionApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Авторизация'), findsOneWidget);
    expect(find.text('Адрес сервера'), findsOneWidget);
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}
