import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';
import 'package:flutter_checks/flutter_checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zulip/api/model/model.dart';
import 'package:zulip/api/model/submessage.dart';
import 'package:zulip/model/store.dart';
import 'package:zulip/widgets/todo.dart';

import '../stdlib_checks.dart';
import '../api/fake_api.dart';
import '../example_data.dart' as eg;
import '../model/binding.dart';
import '../model/test_store.dart';
import 'test_app.dart';

void main() {
  TestZulipBinding.ensureInitialized();

  late PerAccountStore store;
  late FakeApiConnection connection;
  late Message message;

  Future<void> prepareTodoWidget(
    WidgetTester tester,
    SubmessageData? submessageContent, {
    Iterable<(int, bool)> taskCompletedPairs = const [],
  }) async {
    addTearDown(testBinding.reset);
    await testBinding.globalStore.add(eg.selfAccount, eg.initialSnapshot());
    store = await testBinding.globalStore.perAccount(eg.selfAccount.id);
    await store.addUsers([eg.selfUser, eg.otherUser]);
    connection = store.connection as FakeApiConnection;

    message = eg.streamMessage(
      sender: eg.selfUser,
      submessages: [eg.submessage(content: submessageContent)]);
    await store.addMessage(message);
    await tester.pumpWidget(TestZulipApp(accountId: eg.selfAccount.id,
      child: TodoWidget(messageId: message.id, todo: message.todo!)));
    await tester.pump();

    for (final (idx, completed) in taskCompletedPairs) {
      await store.handleEvent(eg.submessageEvent(message.id, eg.selfUser.userId,
        content: TodoStrikeEventSubmessage(
          key: TodoEventSubmessage.taskKey(senderId: null, idx: idx),
          op: completed ? TodoStrikeOp.check : TodoStrikeOp.uncheck)));
    }
    await tester.pump();
  }

  Finder findInTodo(Finder matching) =>
    find.descendant(of: find.byType(TodoWidget), matching: matching);

  testWidgets('smoke', (tester) async {
    await prepareTodoWidget(tester,
      eg.todoWidgetData(taskListTitle: 'Project Tasks', tasks: ['Task A', 'Task B', 'Task C']),
      taskCompletedPairs: [(1, true)]);

    check(findInTodo(find.text('Project Tasks'))).findsOne();
    check(findInTodo(find.text('Task A'))).findsOne();
    check(findInTodo(find.text('Task B'))).findsOne();
    check(findInTodo(find.text('Task C'))).findsOne();
  });

  testWidgets('todo title missing', (tester) async {
    await prepareTodoWidget(tester, eg.todoWidgetData(
      taskListTitle: '', tasks: ['Task A']));
    check(findInTodo(find.text('No title.'))).findsOne();
  });

  testWidgets('todo tasks missing', (tester) async {
    await prepareTodoWidget(tester, eg.todoWidgetData(
      taskListTitle: 'Empty List', tasks: []));
    check(findInTodo(find.text('This todo list has no tasks yet.'))).findsOne();
  });

  void checkStrikeRequest(TodoTaskKey key, TodoStrikeOp op) {
    check(connection.takeRequests()).single.isA<http.Request>()
      ..method.equals('POST')
      ..url.path.equals('/api/v1/submessage')
      ..bodyFields.deepEquals({
        'message_id': jsonEncode(message.id),
        'msg_type': 'widget',
        'content': jsonEncode(TodoStrikeEventSubmessage(key: key, op: op)),
      });
  }

  testWidgets('tap to toggle task completion', (tester) async {
    await prepareTodoWidget(tester, eg.todoWidgetData(
      taskListTitle: 'Tasks', tasks: ['Task A']));
    final taskKey = TodoEventSubmessage.taskKey(senderId: null, idx: 0);

    // Task starts unchecked, so tap to check it
    connection.prepare(json: {});
    final checkbox = findInTodo(find.byType(InkWell)).first;
    await tester.tap(checkbox);
    await tester.pump(Duration.zero);
    checkStrikeRequest(taskKey, TodoStrikeOp.check);

    // Wait for server response to update the todo
    await store.handleEvent(
      eg.submessageEvent(message.id, eg.selfUser.userId,
        content: TodoStrikeEventSubmessage(key: taskKey, op: TodoStrikeOp.check)));
    await tester.pump(Duration.zero);

    // Task is now checked, tap to uncheck it
    connection.prepare(json: {});
    await tester.tap(checkbox);
    await tester.pump(Duration.zero);
    checkStrikeRequest(taskKey, TodoStrikeOp.uncheck);
  });

  testWidgets('multiple tasks with mixed completion states', (tester) async {
    await prepareTodoWidget(tester,
      eg.todoWidgetData(taskListTitle: 'Tasks', tasks: ['Task A', 'Task B', 'Task C']),
      taskCompletedPairs: [(0, true), (2, true)]);

    // Check that all tasks are present
    check(findInTodo(find.text('Task A'))).findsOne();
    check(findInTodo(find.text('Task B'))).findsOne();
    check(findInTodo(find.text('Task C'))).findsOne();

    // Check that we have checkboxes
    check(findInTodo(find.byType(InkWell))).findsAtLeast(3);
  });

  testWidgets('long task list', (tester) async {
    final tasks = List.generate(20, (i) => 'Task #$i');
    await prepareTodoWidget(tester, eg.todoWidgetData(
      taskListTitle: 'Long List', tasks: tasks));

    for (final task in tasks) {
      check(findInTodo(find.text(task))).findsOne();
    }
  });

  testWidgets('task with special characters', (tester) async {
    await prepareTodoWidget(tester, eg.todoWidgetData(
      taskListTitle: 'Special',
      tasks: ['Fix bug #123', 'Review PR @user', 'Deploy to prod 🚀']));

    check(findInTodo(find.text('Fix bug #123'))).findsOne();
    check(findInTodo(find.text('Review PR @user'))).findsOne();
    check(findInTodo(find.text('Deploy to prod 🚀'))).findsOne();
  });
}
