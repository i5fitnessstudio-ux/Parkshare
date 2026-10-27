import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/helpers.dart';
import '../../modules/auth/providers/auth_provider.dart';
import '../../modules/inbox/providers/inbox_provider.dart';
import '../../shared/models/conversation.dart';
import '../../shared/widgets/empty_state.dart';

/// Shared Inbox tab (owner & vehicle user) — real conversations with unread
/// badges. Tap opens the chat screen.
class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final inbox = context.watch<InboxProvider>();
    final conversations = inbox.conversations;

    if (inbox.loading && conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => inbox.loadConversations(auth.accessToken ?? ''),
      child: conversations.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  subtitle: 'Messages about bookings appear here.',
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _ConversationTile(conversation: conversations[i]),
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final party = conversation.otherParty;
    final name = (party?.name ?? '').trim();
    final title = name.isNotEmpty ? name : 'Chat';
    final unread = conversation.unreadCount;
    final time = conversation.lastMessageAt ?? conversation.createdAt;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pushNamed(
          AppRoutes.chat,
          arguments: {
            'conversationId': conversation.id,
            'title': title,
            if ((conversation.parkingName ?? '').trim().isNotEmpty)
              'subtitle': conversation.parkingName!.trim(),
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.userPrimaryLight,
                child: Text(
                  title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.userPrimaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          Helpers.formatDateTime(time),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (conversation.parkingName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        conversation.parkingName!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.lastMessage?.isNotEmpty == true
                                ? conversation.lastMessage!
                                : 'Tap to chat',
                            style: TextStyle(
                              fontSize: 13,
                              color: unread > 0
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.userPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
