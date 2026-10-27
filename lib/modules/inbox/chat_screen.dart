import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../modules/auth/providers/auth_provider.dart';
import '../../modules/inbox/providers/inbox_provider.dart';
import '../../shared/models/conversation.dart';
import '../../shared/widgets/responsive/responsive_layout.dart';

/// Real conversation thread. Route args:
///   { conversationId?, parkingId?, bookingId?, title?, subtitle? }
/// When only parkingId(+bookingId) is given the conversation is created via
/// the ensure-conversation API (owner "Message a customer" / user "Message
/// the owner" actions).
class ChatScreen extends StatefulWidget {
  final Map<String, dynamic>? args;
  const ChatScreen({super.key, this.args});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final inbox = context.read<InboxProvider>();
    final auth = context.read<AuthProvider>();
    // Defer the rest out of the first build phase: InboxProvider.open()
    // notifies listeners synchronously, which would throw
    // "markNeedsBuild() called during build" if it ran inside initState's
    // build.
    await Future<void>.delayed(Duration.zero);
    final token = auth.accessToken ?? '';
    final args = widget.args ?? const {};
    final conversationId = args['conversationId'] as String?;
    final parkingId = args['parkingId'] as String?;
    final bookingId = args['bookingId'] as String?;

    setState(() => _ready = false);
    try {
      if (conversationId != null && conversationId.isNotEmpty) {
        await inbox.open(conversationId: conversationId, token: token);
      } else if (parkingId != null && parkingId.isNotEmpty) {
        final c = await inbox.ensureConversation(
          token: token,
          parkingId: parkingId,
          bookingId: bookingId,
        );
        await inbox.open(conversationId: c.id, token: token);
      }
    } catch (_) {
      _error = 'Could not load the conversation.';
    }
    if (mounted) {
      setState(() => _ready = true);
      _scrollDown(animated: false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final inbox = context.read<InboxProvider>();
    final auth = context.read<AuthProvider>();
    final active = inbox.active;
    if (active == null) return;
    _controller.clear();
    final sent = await inbox.send(
      conversationId: active.id,
      token: auth.accessToken ?? '',
      body: text,
    );
    if (sent != null) {
      _scrollDown();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message not sent. Try again.')),
      );
    }
  }

  void _scrollDown({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Resolves who the thread is with, and which parking it is about.
  ///
  /// Priority for the title: the caller's real name (passed by the booking
  /// card) -> the conversation's `otherParty` name (returned by the inbox
  /// API) -> a last-resort role label. "Parking Owner" is only ever the final
  /// fallback, never the default header.
  (String, String?) _header(Conversation? active) {
    final args = widget.args ?? const {};
    final argTitle = (args['title'] as String?)?.trim() ?? '';
    final otherName = (active?.otherParty?.name ?? '').trim();
    final roleFallback =
        (context.read<AuthProvider>().user?.isVehicleUser ?? true)
        ? 'Parking Owner'
        : 'User';
    final title = argTitle.isNotEmpty
        ? argTitle
        : (otherName.isNotEmpty ? otherName : roleFallback);

    final argSubtitle = (args['subtitle'] as String?)?.trim() ?? '';
    final parkingName = (active?.parkingName ?? '').trim();
    final subtitle = argSubtitle.isNotEmpty
        ? argSubtitle
        : (parkingName.isNotEmpty ? parkingName : null);

    return (title, subtitle);
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<InboxProvider>();
    final meId = context.watch<AuthProvider>().user?.id ?? '';
    final (title, subtitle) = _header(inbox.active);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 17)),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: ConstrainedContent(
        maxWidth: ResponsiveLayout.readingMaxWidth,
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : inbox.messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet. Say hello!',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: inbox.messages.length,
                      itemBuilder: (context, i) {
                        final msg = inbox.messages[i];
                        final mine = msg.senderId == meId;
                        return _Bubble(message: msg, mine: mine);
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: inbox.sending ? null : _send,
                      icon: const Icon(Icons.send),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          // Never wider than 3/4 of the window, and capped at 520 dp so a
          // single message stays readable on a desktop-sized window.
          maxWidth: (MediaQuery.of(context).size.width * 0.75)
              .clamp(200.0, 520.0)
              .toDouble(),
        ),
        decoration: BoxDecoration(
          color: mine ? primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.body,
              style: TextStyle(
                color: mine ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              Helpers.formatDateTime(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: mine ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
