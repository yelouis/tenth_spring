import '../outbox/database.dart';

/// Transport helper payload builders and response handlers for Tenth Spring (protocol v3).
class SyncTransport {
  /// Builds v3 HELLO payload carrying schemaVersion, packVersion, and deviceToken.
  Map<String, dynamic> buildHelloPayload(
    String peerId,
    int schemaVersion,
    String deviceToken, {
    int packVersion = 1,
  }) {
    return {
      "type": "HELLO",
      "peerId": peerId,
      "schemaVersion": schemaVersion,
      "packVersion": packVersion,
      "deviceToken": deviceToken,
    };
  }

  /// Builds v3 BATCH payload from un-synced explore outbox items.
  /// Contains only the v3 fields (`seq`, `kind`, `placeId`, `areaKey` for explore, `tsUtcMs`);
  /// never carries coordinates or `bodyFix`.
  Map<String, dynamic> buildBatchPayload(List<ExploreOutboxItem> rows) {
    final rowList = rows.map((r) {
      if (r.kind == 'home') {
        return <String, dynamic>{
          "seq": r.seq,
          "kind": "home",
          "placeId": r.placeId,
          "tsUtcMs": r.tsUtcMs,
        };
      }
      return <String, dynamic>{
        "seq": r.seq,
        "kind": r.kind,
        "placeId": r.placeId,
        if (r.areaKey != null) "areaKey": r.areaKey,
        "tsUtcMs": r.tsUtcMs,
      };
    }).toList();

    return {
      "type": "BATCH",
      "rows": rowList,
    };
  }

  /// Handles ACK response and purges applied outbox items up to lastAppliedSeq.
  Future<int> handleAckResponse(
    Map<String, dynamic> ackPayload,
    AppDatabase db,
  ) async {
    if (ackPayload['status'] == 'ack' &&
        ackPayload.containsKey('lastAppliedSeq')) {
      final lastAppliedSeq = ackPayload['lastAppliedSeq'] as int;
      await db.deleteSyncedUpTo(lastAppliedSeq);
      return lastAppliedSeq;
    }
    return 0;
  }
}
