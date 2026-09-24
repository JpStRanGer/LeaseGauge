import 'package:flutter/material.dart';

class InfoHelpItem {
  const InfoHelpItem({required this.heading, required this.description});

  final String heading;
  final String description;
}

class InfoHelpButton extends StatelessWidget {
  const InfoHelpButton({
    super.key,
    required this.title,
    required this.introduction,
    this.items = const [],
    this.iconColor,
  });

  final String title;
  final String introduction;
  final List<InfoHelpItem> items;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Help: $title',
      color: iconColor,
      icon: const Icon(Icons.help_outline_rounded),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(introduction),
                for (final item in items) ...[
                  const SizedBox(height: 16),
                  Text(
                    item.heading,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(item.description),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
