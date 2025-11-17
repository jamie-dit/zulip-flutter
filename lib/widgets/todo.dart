import 'dart:async';

import 'package:flutter/material.dart';

import '../api/model/submessage.dart';
import '../api/route/submessage.dart';
import '../generated/l10n/zulip_localizations.dart';
import 'content.dart';
import 'store.dart';
import 'text.dart';

class TodoWidget extends StatefulWidget {
  const TodoWidget({super.key, required this.messageId, required this.todo});

  final int messageId;
  final Todo todo;

  @override
  State<TodoWidget> createState() => _TodoWidgetState();
}

class _TodoWidgetState extends State<TodoWidget> {
  @override
  void initState() {
    super.initState();
    widget.todo.addListener(_modelChanged);
  }

  @override
  void didUpdateWidget(covariant TodoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.todo != oldWidget.todo) {
      oldWidget.todo.removeListener(_modelChanged);
      widget.todo.addListener(_modelChanged);
    }
  }

  @override
  void dispose() {
    widget.todo.removeListener(_modelChanged);
    super.dispose();
  }

  void _modelChanged() {
    setState(() {
      // The actual state lives in the [Todo] model.
      // This method was called because that just changed.
    });
  }

  void _toggleTask(TodoTask task) async {
    final store = PerAccountStoreWidget.of(context);
    final op = task.completed
      ? TodoStrikeOp.uncheck
      : TodoStrikeOp.check;
    unawaited(sendSubmessage(store.connection, messageId: widget.messageId,
      submessageType: SubmessageType.widget,
      content: TodoStrikeEventSubmessage(key: task.key, op: op)));
  }

  @override
  Widget build(BuildContext context) {
    const verticalPadding = 2.5;

    final zulipLocalizations = ZulipLocalizations.of(context);
    final theme = ContentTheme.of(context);

    final textStyleBold = weightVariableTextStyle(context, wght: 600);
    final textStyleTask = TextStyle(fontSize: 16, color: theme.textStylePlainParagraph.color);
    final textStyleCompleted = textStyleTask.copyWith(
      decoration: TextDecoration.lineThrough,
      color: theme.textStylePlainParagraph.color!.withOpacity(0.6),
    );

    Text title = (widget.todo.taskListTitle.isNotEmpty)
      ? Text(widget.todo.taskListTitle, style: textStyleBold.copyWith(fontSize: 18))
      : Text(zulipLocalizations.todoWidgetTitleMissing,
          style: textStyleBold.copyWith(fontSize: 18, fontStyle: FontStyle.italic));

    Widget buildTaskItem(TodoTask task) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: 8, top: verticalPadding, bottom: verticalPadding),
              child: Material(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                  side: BorderSide(color: theme.colorPollVoteCountBorder)),
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _toggleTask(task),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      task.completed ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 24,
                      color: theme.colorPollVoteCountText,
                    ))))),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: verticalPadding),
              child: Text(task.text, style: task.completed ? textStyleCompleted : textStyleTask),
            )),
        ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        // `verticalPadding` out of 6px comes from the first task row.
        const SizedBox(height: 6 - verticalPadding),
        if (widget.todo.tasks.isEmpty)
          Padding(
            // This is consistent with the task rows' padding.
            padding: const EdgeInsets.symmetric(vertical: verticalPadding),
            child: Text(zulipLocalizations.todoWidgetTasksMissing,
              style: textStyleTask.copyWith(fontStyle: FontStyle.italic))),
        for (final task in widget.todo.tasks)
          buildTaskItem(task),
        // `verticalPadding` out of 5px comes from the last task row.
        const SizedBox(height: 5 - verticalPadding),
      ]);
  }
}
