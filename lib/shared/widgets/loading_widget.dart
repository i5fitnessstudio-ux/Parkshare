import 'package:flutter/material.dart';

/// Centered loading indicator with optional label.
class LoadingWidget extends StatelessWidget {
  final String? label;

  const LoadingWidget({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(
              label!,
              style: const TextStyle(fontSize: 15, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
