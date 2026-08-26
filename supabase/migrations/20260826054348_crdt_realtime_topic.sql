-- CRDT collaboration, phase 5. Continues 20260826054316_yjs_durability_tables.sql.

-- --------------------------------------------------------------- Realtime --

-- `crdt:<kbId>` is client-written, like `presence:<kbId>` and unlike
-- `kb:<kbId>`. See 20260825184402_presence_channel.sql: the notification bus
-- must never gain `insert`, because a client able to write there could forge a
-- document_published event. A third topic keeps this write grant away from it.
--
-- What rides here is opaque Yjs update bytes, which are only meaningful to a
-- peer that already has the document — and every subscriber is a member of the
-- Knowledge Base, so they all do.
--
-- `substring(... from 6)` drops the 'crdt:' prefix, which is five characters.
create policy kb_members_read_crdt on realtime.messages
  for select to authenticated
  using (
    realtime.topic() like 'crdt:%'
    and (select private.is_kb_member(substring(realtime.topic() from 6)::uuid))
  );

-- Broadcasting an update requires an editing role, not merely membership: a
-- reviewer who cannot publish must not be able to push document content at
-- everyone else's editor either.
create policy kb_editors_write_crdt on realtime.messages
  for insert to authenticated
  with check (
    realtime.topic() like 'crdt:%'
    and (
      select coalesce(
        private.kb_member_role_rank(substring(realtime.topic() from 6)::uuid), 0
      ) > 0
    )
  );
