import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class BreadcrumbWidget extends StatelessWidget {
  const BreadcrumbWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final segments = appState.breadcrumbSegments;

    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () => appState.navigateToBreadcrumb(0),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.home,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            
            ...List.generate(segments.length, (index) {
              final isLast = index == segments.length - 1;
              
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0 || segments.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  
                  InkWell(
                    onTap: isLast ? null : () => appState.navigateToBreadcrumb(index),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        segments[index],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                          color: isLast
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
