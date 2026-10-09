import '../outbox/database.dart';

/// Transport helper payload builders and response handlers for Tenth Spring.
class SyncTransport {
  /// Builds HELLO payload carrying deviceToken
  Map<String, dynamic> buildHelloPayload(String peerId, int schemaVersion, String deviceToken) {
    return {
      "type": "HELLO",
      "peerId": peerId,
      "schemaVersion": schemaVersion,
      "deviceToken": deviceToken,
    };
  }

  /// Builds BATCH payload from un-synced outbox items
  Map<String, dynamic> buildBatchPayload(List<VisitOutboxItem> rows, Map<String, dynamic> bodyFix) {
    final rowList = rows.map((r) => {
      "seq": r.seq,
      "kind": r.kind,
      "lat": r.lat,
      "lon": r.lon,
      "startedAt": r.startedAt,
      if (r.dwellSeconds != null) "dwellSeconds": r.dwellSeconds,
    }).toList();

    return {
      "type": "BATCH",
      "rows": rowList,
      "bodyFix": bodyFix,
    };
  }

  /// Handles ACK response and purges applied outbox items up to lastAppliedSeq
  Future<int> handleAckResponse(Map<String, dynamic> ackPayload, AppDatabase db) async {
    if (ackPayload['status'] == 'ack' && ackPayload.containsKey('lastAppliedSeq')) {
      final lastAppliedSeq = ackPayload['lastAppliedSeq'] as int;
      await db.deleteSyncedUpTo(lastAppliedSeq);
      return lastAppliedSeq;
    }
    return 0;
  }
}
