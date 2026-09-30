import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

typedef ActionCallback = void Function(Map<String, dynamic> action);

/// Renders LINE TemplateSendMessage widgets: Buttons, Confirm, and Carousel.
class TemplateMessageWidget extends StatelessWidget {
  final Map<String, dynamic> templateData;
  final ActionCallback onAction;

  const TemplateMessageWidget({
    super.key,
    required this.templateData,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final type = templateData['type'] ?? '';

    switch (type) {
      case 'buttons':
        return _buildButtonsTemplate(context, templateData);
      case 'confirm':
        return _buildConfirmTemplate(context, templateData);
      case 'carousel':
        return _buildCarouselTemplate(context, templateData);
      default:
        return Text(templateData['text'] ?? '未知模板訊息');
    }
  }

  Widget _buildButtonsTemplate(BuildContext context, Map<String, dynamic> data) {
    final imageUrl = data['thumbnailImageUrl'];
    final title = data['title'];
    final text = data['text'] ?? '';
    final actions = (data['actions'] as List? ?? []).cast<Map<String, dynamic>>();

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.toString().isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              height: 140,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 140,
                color: Colors.grey.shade200,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 140,
                color: Colors.grey.shade300,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.toString().isNotEmpty) ...[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                ),
              ],
            ),
          ),
          ...actions.map((act) => Column(
                children: [
                  const Divider(height: 1, thickness: 1),
                  InkWell(
                    onTap: () => onAction(act),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Text(
                        act['label'] ?? act['text'] ?? '選項',
                        style: const TextStyle(
                          color: Color(0xFF007AFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildConfirmTemplate(BuildContext context, Map<String, dynamic> data) {
    final text = data['text'] ?? '';
    final actions = (data['actions'] as List? ?? []).cast<Map<String, dynamic>>();

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Row(
            children: actions.map((act) {
              final isLast = act == actions.last;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => onAction(act),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            act['label'] ?? act['text'] ?? '確認',
                            style: const TextStyle(
                              color: Color(0xFF007AFF),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!isLast) const VerticalDivider(width: 1, thickness: 1),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselTemplate(BuildContext context, Map<String, dynamic> data) {
    final columns = (data['columns'] as List? ?? []).cast<Map<String, dynamic>>();

    return SizedBox(
      height: 310,
      child: ListView.separated(
        padding: const EdgeInsets.only(right: 12),
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: columns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final col = columns[index];
          return _buildButtonsTemplate(context, col);
        },
      ),
    );
  }
}
