import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Differences migration preserves scoped reviewed-edit invariants',
    () async {
      final sql = await File(
        'supabase/migrations/20260822193140_differences_reviewed_edit_workflow.sql',
      ).readAsString();
      final baseline = await File(
        'supabase/migrations/20260821120000_collaboration_roles_and_review_queue.sql',
      ).readAsString();

      expect(sql, contains("array['editor', 'co_owner']::text[]"));
      expect(
        baseline,
        contains('change_sets_one_pending_per_author_document_idx'),
      );
      expect(baseline, contains('where status = \'pending\''));
      expect(sql, contains('private.can_manage_kb(p_kb_id)'));
      expect(sql, contains('and author_id = v_uid'));
      expect(sql, contains("set status = 'withdrawn'"));
      expect(sql, contains('security invoker'));
      expect(sql, contains('set search_path = \'\''));
      expect(sql, contains('from public, anon'));
      expect(sql, isNot(contains('grant all')));
      expect(sql, isNot(contains('service_role')));
      expect(baseline, contains('p_expected_current_revision'));
      expect(baseline, contains('for update'));
      expect(sql, contains('private.publish_document_directly'));
      expect(sql, contains('v_doc.current_revision_id is distinct from'));
      expect(sql, contains("using errcode = '40001'"));
      expect(sql, contains('returning id into v_revision_id'));
    },
  );

  test('protected publishing migration routes and locks server-side', () async {
    final sql = await File(
      'supabase/migrations/20260822203229_protected_document_publishing.sql',
    ).readAsString();

    expect(sql, contains('documents_protection_consistent'));
    expect(sql, contains("protection_class = 'protected'"));
    expect(sql, contains('private.set_document_protection'));
    expect(sql, contains('private.publish_document_change'));
    expect(sql, contains("'outcome', 'proposed'"));
    expect(sql, contains("'outcome', 'published'"));
    expect(sql, contains('for update'));
    expect(sql, contains('v_doc.current_revision_id is distinct from'));
    expect(sql, contains("using errcode = '40001'"));
    expect(sql, contains('private.can_publish_document(kb_id, id)'));
    expect(sql, contains('document_published'));
    expect(sql, contains('document_protection_changed'));
    expect(sql, contains('perform realtime.send'));
    expect(sql, contains('security invoker'));
    expect(sql, contains("set search_path = ''"));
    expect(sql, isNot(contains('grant all')));
    expect(sql, isNot(contains('service_role')));
    expect(
      sql,
      contains('and author_id = v_uid'),
      reason: 'direct publish may withdraw only the publisher\'s own draft',
    );
  });
}
