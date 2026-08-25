-- Live presence: which document, and which block, a collaborator is in.
--
-- Presence is ephemeral. Realtime holds it per connection, syncs it to the
-- other subscribers, and drops it when the socket closes. Nothing is written
-- to a table, no revision is created, and the reviewed-edit model is untouched.
--
-- The payload carries a user id, a username, a display name, a document path,
-- a document id and a block id — identifiers only, never document content.
-- That is the same rule `kb:<uuid>` already follows.

-- --------------------------------------------------------------- Realtime --

-- A separate topic from `kb:<uuid>`, and separate on purpose.
--
-- `kb:<uuid>` is the trigger-driven notification bus: the server publishes
-- proposal_created, document_published and document_protection_changed on it,
-- and clients only ever read. Presence is the opposite — it is sent by the
-- client — so it needs `insert` on realtime.messages, which `kb:<uuid>` must
-- never grant. A client able to insert there could forge a publish
-- notification and drive another member's sync. Splitting the topic keeps the
-- write grant away from the bus that is trusted to be server-authored.
--
-- `substring(... from 10)` drops the 'presence:' prefix, which is nine
-- characters, leaving the Knowledge Base uuid.

create policy kb_members_read_presence on realtime.messages
  for select to authenticated
  using (
    realtime.topic() like 'presence:%'
    and (select private.is_kb_member(substring(realtime.topic() from 10)::uuid))
  );

create policy kb_members_write_presence on realtime.messages
  for insert to authenticated
  with check (
    realtime.topic() like 'presence:%'
    and (select private.is_kb_member(substring(realtime.topic() from 10)::uuid))
  );

-- `private.is_kb_member` requires `accepted_at is not null`, so somebody who
-- has been invited but has not accepted can neither be seen nor see.
