import 'package:flutter/material.dart';

class StandardBackButton extends StatelessWidget {
  const StandardBackButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Regresar',
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
      ),
    );
  }
}

class StandardSectionHeader extends StatelessWidget {
  const StandardSectionHeader({
    super.key,
    required this.title,
    required this.onBack,
    required this.backgroundColor,
    this.subtitle,
    this.backTooltip = 'Regresar',
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final Color backgroundColor;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              StandardBackButton(onPressed: onBack, tooltip: backTooltip),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
