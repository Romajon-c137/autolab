import 'package:flutter/material.dart';

class DocumentHtmlView extends StatelessWidget {
  const DocumentHtmlView({
    super.key,
    required this.brand,
    required this.country,
    required this.vin,
  });

  final String brand;
  final String country;
  final String vin;

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(child: Text('Документ доступен в web-режиме')),
    );
  }
}
