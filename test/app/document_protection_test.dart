import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publish ranks are ordered Editor, Co-Owner, Owner', () {
    expect(KbRole.editor.meets(MinimumPublishRole.editor), isTrue);
    expect(KbRole.editor.meets(MinimumPublishRole.coOwner), isFalse);
    expect(KbRole.coOwner.meets(MinimumPublishRole.editor), isTrue);
    expect(KbRole.coOwner.meets(MinimumPublishRole.owner), isFalse);
    expect(KbRole.owner.meets(MinimumPublishRole.owner), isTrue);
    expect(KbRole.reviewer.publishingRank, isNull);
  });

  test('protection and publish receipts decode database values', () {
    final protection = DocumentProtection.fromRow(const {
      'protection_class': 'protected',
      'minimum_publish_role': 'co_owner',
    });
    expect(protection?.minimumPublishRole, MinimumPublishRole.coOwner);
    expect(
      DocumentPublishReceipt.fromRpc(const {
        'outcome': 'proposed',
        'id': 'proposal-1',
      }).disposition,
      DocumentPublishDisposition.proposed,
    );
  });
}
